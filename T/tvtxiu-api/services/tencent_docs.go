package services

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"tvtxiu-api/models"

	"github.com/google/uuid"
)

// TencentDocsService 腾讯文档服务
type TencentDocsService struct {
	Cookie string
	DocURL string
	TabID  string
}

// NewTencentDocsService 创建腾讯文档服务
func NewTencentDocsService(cookie, docURL, tabID string) *TencentDocsService {
	// 清理 Cookie 中的无效字符（换行、制表符、多余空格等）
	cleanCookie := strings.ReplaceAll(cookie, "\n", "")
	cleanCookie = strings.ReplaceAll(cleanCookie, "\r", "")
	cleanCookie = strings.ReplaceAll(cleanCookie, "\t", "")
	cleanCookie = strings.TrimSpace(cleanCookie)

	return &TencentDocsService{
		Cookie: cleanCookie,
		DocURL: docURL,
		TabID:  tabID,
	}
}

// FetchShootingOrders 从腾讯文档获取拍摄订单
func (s *TencentDocsService) FetchShootingOrders(year int) ([]models.ShootingOrder, error) {
	// 构建请求URL
	// 腾讯文档的数据接口格式
	docID := s.extractDocID()
	if docID == "" {
		return nil, fmt.Errorf("无法解析文档ID")
	}

	// 尝试获取表格数据
	apiURL := fmt.Sprintf("https://docs.qq.com/dop-api/opendoc?id=%s&tab=%s&outformat=1&normal=1", docID, s.TabID)

	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return nil, fmt.Errorf("创建请求失败: %w", err)
	}

	// 设置请求头
	req.Header.Set("Cookie", s.Cookie)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Referer", s.DocURL)

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("请求失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("请求返回错误状态码: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("读取响应失败: %w", err)
	}

	// 临时：保存完整响应到文件用于调试
	os.WriteFile("/tmp/tencent_full_response.json", body, 0644)
	log.Printf("[TencentDocs] 完整响应已保存到 /tmp/tencent_full_response.json (大小: %d 字节)", len(body))

	// 解析响应数据
	orders, err := s.parseTableData(body, year)
	if err != nil {
		return nil, fmt.Errorf("解析数据失败: %w", err)
	}

	return orders, nil
}

// extractDocID 从URL中提取文档ID
func (s *TencentDocsService) extractDocID() string {
	// URL格式: https://docs.qq.com/sheet/DY1B6ZEV6c3BxUkNR?tab=rq41oz
	re := regexp.MustCompile(`docs\.qq\.com/sheet/([A-Za-z0-9]+)`)
	matches := re.FindStringSubmatch(s.DocURL)
	if len(matches) >= 2 {
		return matches[1]
	}
	return ""
}

// parseTableData 解析表格数据
func (s *TencentDocsService) parseTableData(data []byte, filterYear int) ([]models.ShootingOrder, error) {
	var orders []models.ShootingOrder

	// 打印响应预览以便调试
	preview := string(data)
	if len(preview) > 500 {
		preview = preview[:500] + "..."
	}
	log.Printf("[TencentDocs] 响应预览: %s", preview)

	// 尝试解析JSON响应
	var response map[string]interface{}
	if err := json.Unmarshal(data, &response); err != nil {
		// 如果不是JSON，可能需要其他解析方式
		previewLen := 200
		if len(data) < previewLen {
			previewLen = len(data)
		}
		log.Printf("[TencentDocs] JSON解析失败，原始响应前200字符: %s", string(data[:previewLen]))
		return nil, fmt.Errorf("JSON解析失败: %w", err)
	}

	// 打印顶层键
	var keys []string
	for k := range response {
		keys = append(keys, k)
	}
	log.Printf("[TencentDocs] 响应顶层键: %v", keys)

	// 腾讯文档的响应结构可能是：
	// { "clientVars": { "initialAttributedText": { "text": [...] } } }
	// 或其他格式，需要根据实际响应调整

	// 获取表格数据
	clientVars, ok := response["clientVars"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("响应格式不正确: 缺少 clientVars")
	}

	// 打印 clientVars 内部的键
	var clientVarsKeys []string
	for k := range clientVars {
		clientVarsKeys = append(clientVarsKeys, k)
	}
	log.Printf("[TencentDocs] clientVars 键: %v", clientVarsKeys)

	// 尝试多种可能的路径查找表格数据
	var initialText map[string]interface{}

	// 直接从 clientVars 查找
	if data, ok := clientVars["initialAttributedText"].(map[string]interface{}); ok {
		initialText = data
	}

	// 从 collab_client_vars 查找
	if initialText == nil {
		if collabVars, ok := clientVars["collab_client_vars"].(map[string]interface{}); ok {
			log.Printf("[TencentDocs] 找到 collab_client_vars，键: %v", getKeys(collabVars))
			if data, ok := collabVars["initialAttributedText"].(map[string]interface{}); ok {
				initialText = data
			}
		}
	}

	if initialText == nil {
		log.Printf("[TencentDocs] 未找到 initialAttributedText，尝试解析替代格式")
		return s.parseAlternativeFormat(response, filterYear)
	}

	// 打印 initialText 的键
	log.Printf("[TencentDocs] initialAttributedText 键: %v", getKeys(initialText))

	// 查找表格数据 - 可能在 text 或其他位置
	textData, ok := initialText["text"].([]interface{})
	if !ok {
		// 尝试 rows 或其他字段
		if rows, ok := initialText["rows"].([]interface{}); ok {
			textData = rows
		} else {
			log.Printf("[TencentDocs] 未找到 text/rows 数据，initialText 内容预览")
			// 打印部分内容帮助调试
			for k, v := range initialText {
				vStr := fmt.Sprintf("%v", v)
				if len(vStr) > 100 {
					vStr = vStr[:100] + "..."
				}
				log.Printf("[TencentDocs]   %s: %s", k, vStr)
			}
			return nil, fmt.Errorf("响应格式不正确: 缺少 text 数据")
		}
	}

	log.Printf("[TencentDocs] 找到 %d 行数据", len(textData))

	// 打印第一行数据结构以便调试
	if len(textData) > 0 {
		first := textData[0]
		firstType := fmt.Sprintf("%T", first)
		firstStr := fmt.Sprintf("%v", first)
		if len(firstStr) > 200 {
			firstStr = firstStr[:200] + "..."
		}
		log.Printf("[TencentDocs] 第一行类型: %s, 内容: %s", firstType, firstStr)
	}

	// 解析每一行数据
	// 跳过表头行（通常是前2行）
	for i := 2; i < len(textData); i++ {
		row, ok := textData[i].([]interface{})
		if !ok || len(row) < 10 {
			continue
		}

		order, err := s.parseRow(row, filterYear)
		if err != nil {
			continue // 跳过解析失败的行
		}
		if order != nil {
			orders = append(orders, *order)
		}
	}

	return orders, nil
}

// parseAlternativeFormat 尝试解析其他格式
func (s *TencentDocsService) parseAlternativeFormat(response map[string]interface{}, filterYear int) ([]models.ShootingOrder, error) {
	// 这里需要根据实际的腾讯文档API响应格式进行调整
	// 可能需要处理CSV格式或其他数据格式
	return nil, fmt.Errorf("需要根据实际响应格式调整解析逻辑")
}

// parseRow 解析单行数据
func (s *TencentDocsService) parseRow(row []interface{}, filterYear int) (*models.ShootingOrder, error) {
	// 根据表格结构：
	// 0: 序号, 1: 订单编号, 2: 年, 3: 月, 4: 日, 5: 地点, 6: 国家, 7: 类型, 8-N: 拍摄人员...

	// 获取年份
	year := s.toInt(row[2])
	if year != filterYear {
		return nil, nil // 跳过非目标年份
	}

	order := &models.ShootingOrder{
		ID:          uuid.New(),
		OrderNumber: s.toString(row[1]),
		ShootYear:   year,
		ShootMonth:  s.toInt(row[3]),
		ShootDay:    s.toString(row[4]),
		Location:    s.toString(row[5]),
		Country:     s.toString(row[6]),
		OrderType:   s.toString(row[7]),
		SyncedAt:    time.Now(),
	}

	// 拍摄人员可能在多列，取第一个非空值
	for i := 8; i < len(row) && i < 15; i++ {
		photographer := s.toString(row[i])
		if photographer != "" && photographer != "pvm" && photographer != "pvm偶" {
			order.Photographer = photographer
			break
		}
	}

	// 计算拍摄日期
	order.ComputeShootDate()

	// 保存原始数据
	rawData, _ := json.Marshal(row)
	order.RawData = string(rawData)

	return order, nil
}

// toString 转换为字符串
func (s *TencentDocsService) toString(v interface{}) string {
	if v == nil {
		return ""
	}
	switch val := v.(type) {
	case string:
		return strings.TrimSpace(val)
	case float64:
		return fmt.Sprintf("%.0f", val)
	case int:
		return strconv.Itoa(val)
	default:
		return fmt.Sprintf("%v", v)
	}
}

// toInt 转换为整数
func (s *TencentDocsService) toInt(v interface{}) int {
	if v == nil {
		return 0
	}
	switch val := v.(type) {
	case float64:
		return int(val)
	case int:
		return val
	case string:
		i, _ := strconv.Atoi(val)
		return i
	default:
		return 0
	}
}

// getKeys 获取 map 的所有键
func getKeys(m map[string]interface{}) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

// TestConnection 测试连接
func (s *TencentDocsService) TestConnection() error {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", s.DocURL, nil)
	if err != nil {
		return err
	}

	req.Header.Set("Cookie", s.Cookie)
	req.Header.Set("User-Agent", "Mozilla/5.0")

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("连接失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Cookie 无效或文档无访问权限 (状态码: %d)", resp.StatusCode)
	}

	return nil
}
