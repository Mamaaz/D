package services

import (
	"fmt"
	"log"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"tvtxiu-api/models"

	"github.com/google/uuid"
	"github.com/xuri/excelize/v2"
)

// ExcelParserService Excel 解析服务
type ExcelParserService struct{}

// NewExcelParserService 创建 Excel 解析服务
func NewExcelParserService() *ExcelParserService {
	return &ExcelParserService{}
}

// ParseResult 解析结果
type ParseResult struct {
	Orders      []models.ShootingOrder `json:"orders"`
	TotalRows   int                    `json:"totalRows"`
	ValidRows   int                    `json:"validRows"`
	SkippedRows int                    `json:"skippedRows"`
	ByYear      map[int]int            `json:"byYear"`
	Errors      []string               `json:"errors"`
}

// ColumnMapping 列映射配置
type ColumnMapping struct {
	OrderNumber  int // 订单编号列（通常从数据中提取）
	Month        int // 拍月
	Day          int // 拍日
	Location     int // 实时地点
	Country      int // 实时国家
	OrderType    int // 拍摄类型
	Sales        int // 销售
	Consultant   int // 顾问
	Photographer int // 摄影师
	PostProducer int // 后期师
}

// dateLocation 日期地点组合
type dateLocation struct {
	month    int
	day      string
	location string
}

// ParseExcelFile 解析 Excel 文件
func (s *ExcelParserService) ParseExcelFile(filePath string, targetYears []int) (*ParseResult, error) {
	f, err := excelize.OpenFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("打开文件失败: %w", err)
	}
	defer f.Close()

	// 临时存储：所有未合并的订单
	var allOrders []models.ShootingOrder

	result := &ParseResult{
		Orders: make([]models.ShootingOrder, 0),
		ByYear: make(map[int]int),
	}

	// 获取所有 Sheet
	sheets := f.GetSheetList()
	log.Printf("[ExcelParser] 找到 %d 个 Sheet", len(sheets))

	for _, sheetName := range sheets {
		// 从 Sheet 名提取年份
		year := s.extractYearFromSheetName(sheetName)
		if year == 0 {
			log.Printf("[ExcelParser] 跳过 Sheet: %s (无法识别年份)", sheetName)
			continue
		}

		// 如果指定了目标年份，检查是否在列表中
		if len(targetYears) > 0 && !contains(targetYears, year) {
			log.Printf("[ExcelParser] 跳过 Sheet: %s (不在目标年份列表)", sheetName)
			continue
		}

		log.Printf("[ExcelParser] 解析 Sheet: %s (年份: %d)", sheetName, year)

		// 解析该 Sheet
		orders, stats, errs := s.parseSheet(f, sheetName, year)
		allOrders = append(allOrders, orders...)
		result.TotalRows += stats.total
		result.ValidRows += stats.valid
		result.SkippedRows += stats.skipped
		result.Errors = append(result.Errors, errs...)
	}

	// 合并同一订单号的多行记录
	mergedOrders := s.mergeOrdersByOrderNumber(allOrders)
	result.Orders = mergedOrders

	// 按年份统计
	for _, order := range mergedOrders {
		result.ByYear[order.ShootYear]++
	}

	log.Printf("[ExcelParser] 解析完成: 总共 %d 行, 有效 %d 行, 合并后 %d 条订单",
		result.TotalRows, result.ValidRows, len(mergedOrders))

	return result, nil
}

type sheetStats struct {
	total   int
	valid   int
	skipped int
}

// parseSheet 解析单个 Sheet
func (s *ExcelParserService) parseSheet(f *excelize.File, sheetName string, year int) ([]models.ShootingOrder, sheetStats, []string) {
	var orders []models.ShootingOrder
	var errors []string
	stats := sheetStats{}

	rows, err := f.GetRows(sheetName)
	if err != nil {
		return nil, stats, []string{fmt.Sprintf("读取 Sheet %s 失败: %v", sheetName, err)}
	}

	if len(rows) < 3 {
		return nil, stats, nil // 空表
	}

	// 智能检测表头行：查找包含"订单编号"的行
	headerRowIndex := -1
	for i := 0; i < min(10, len(rows)); i++ { // 只搜索前10行
		for _, cell := range rows[i] {
			if strings.Contains(cell, "订单编号") {
				headerRowIndex = i
				break
			}
		}
		if headerRowIndex >= 0 {
			break
		}
	}

	if headerRowIndex < 0 {
		log.Printf("[ExcelParser] Sheet %s: 未找到表头行", sheetName)
		return nil, stats, nil
	}

	log.Printf("[ExcelParser] Sheet %s: 表头在第 %d 行", sheetName, headerRowIndex+1)

	// 解析表头，建立列映射
	headerRow := rows[headerRowIndex]
	mapping := s.parseHeader(headerRow)
	log.Printf("[ExcelParser] 列映射: 订单号=%d, 月=%d, 日=%d, 地点=%d, 类型=%d, 修图师=%d",
		mapping.OrderNumber, mapping.Month, mapping.Day, mapping.Location, mapping.OrderType, mapping.PostProducer)

	// 遍历数据行（从表头下一行开始）
	for i := headerRowIndex + 1; i < len(rows); i++ {
		row := rows[i]
		stats.total++

		order, err := s.parseRow(row, mapping, year, i+1)
		if err != nil {
			stats.skipped++
			continue // 跳过无效行
		}

		if order != nil {
			orders = append(orders, *order)
			stats.valid++
		} else {
			stats.skipped++
		}
	}

	return orders, stats, errors
}

// min 返回两个整数中较小的那个
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// parseHeader 解析表头，返回列映射
func (s *ExcelParserService) parseHeader(header []string) ColumnMapping {
	mapping := ColumnMapping{
		OrderNumber:  -1,
		Month:        -1,
		Day:          -1,
		Location:     -1,
		Country:      -1,
		OrderType:    -1,
		Sales:        -1,
		Consultant:   -1,
		Photographer: -1,
		PostProducer: -1,
	}

	for i, col := range header {
		col = strings.TrimSpace(col)
		switch {
		case col == "订单编号":
			mapping.OrderNumber = i
		case col == "拍月":
			mapping.Month = i
		case col == "拍日":
			mapping.Day = i
		case col == "实时地点" || strings.Contains(col, "地点"):
			mapping.Location = i
		case col == "实时国家" || strings.Contains(col, "国家"):
			mapping.Country = i
		case col == "拍摄类型":
			mapping.OrderType = i
		case col == "销售":
			mapping.Sales = i
		case col == "顾问":
			mapping.Consultant = i
		case col == "p" || strings.Contains(col, "摄影"):
			if mapping.Photographer < 0 { // 只取第一个
				mapping.Photographer = i
			}
		case col == "修图师" || strings.Contains(col, "后期师"):
			mapping.PostProducer = i
		}
	}

	return mapping
}

// parseRow 解析单行数据
func (s *ExcelParserService) parseRow(row []string, mapping ColumnMapping, year int, rowNum int) (*models.ShootingOrder, error) {
	// 获取订单编号 - 可能在固定列，也可能需要从其他列提取
	orderNumber := ""

	// 首先尝试从指定列获取
	if mapping.OrderNumber >= 0 && mapping.OrderNumber < len(row) {
		orderNumber = strings.TrimSpace(row[mapping.OrderNumber])
	}

	// 如果没有，尝试从整行查找 CS/FG 开头的订单号
	if orderNumber == "" || !isValidOrderNumber(orderNumber) {
		for _, cell := range row {
			cell = strings.TrimSpace(cell)
			if isValidOrderNumber(cell) {
				orderNumber = cell
				break
			}
		}
	}

	if orderNumber == "" {
		return nil, nil // 没有订单号，跳过
	}

	// 获取必要字段
	month := s.getIntValue(row, mapping.Month)
	day := s.getStringValue(row, mapping.Day)
	location := s.getStringValue(row, mapping.Location)

	// 验证必要字段
	if location == "" {
		return nil, nil // 没有地点，跳过
	}

	order := &models.ShootingOrder{
		ID:           uuid.New(),
		OrderNumber:  orderNumber,
		ShootYear:    year,
		ShootMonth:   month,
		ShootDay:     day,
		Location:     location,
		Country:      s.getStringValue(row, mapping.Country),
		OrderType:    s.getStringValue(row, mapping.OrderType),
		Sales:        s.getStringValue(row, mapping.Sales),
		Consultant:   s.getStringValue(row, mapping.Consultant),
		Photographer: s.getStringValue(row, mapping.Photographer),
		SyncedAt:     time.Now(),
	}

	// 计算拍摄日期
	order.ComputeShootDate()

	return order, nil
}

// extractYearFromSheetName 从 Sheet 名提取年份
func (s *ExcelParserService) extractYearFromSheetName(name string) int {
	// 匹配格式: "2024年拍摄订单" 或 "2024年1月" 等
	re := regexp.MustCompile(`(\d{4})年`)
	matches := re.FindStringSubmatch(name)
	if len(matches) >= 2 {
		year, err := strconv.Atoi(matches[1])
		if err == nil && year >= 2000 && year <= 2100 {
			return year
		}
	}
	return 0
}

// getStringValue 获取字符串值
func (s *ExcelParserService) getStringValue(row []string, index int) string {
	if index < 0 || index >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[index])
}

// getIntValue 获取整数值
func (s *ExcelParserService) getIntValue(row []string, index int) int {
	str := s.getStringValue(row, index)
	if str == "" {
		return 0
	}
	// 处理可能的浮点数格式 (Excel 有时会存储为 1.0)
	if strings.Contains(str, ".") {
		f, err := strconv.ParseFloat(str, 64)
		if err == nil {
			return int(f)
		}
	}
	val, _ := strconv.Atoi(str)
	return val
}

// isValidOrderNumber 检查是否是有效的订单编号
func isValidOrderNumber(s string) bool {
	if len(s) < 5 {
		return false
	}
	// 以 CS/FG/FE 等开头
	prefixes := []string{"CS", "FG", "FE"}
	for _, prefix := range prefixes {
		if strings.HasPrefix(strings.ToUpper(s), prefix) {
			return true
		}
	}
	return false
}

// contains 检查切片是否包含元素
func contains(slice []int, item int) bool {
	for _, v := range slice {
		if v == item {
			return true
		}
	}
	return false
}

// mergeOrdersByOrderNumber 合并同一订单号的多行记录
func (s *ExcelParserService) mergeOrdersByOrderNumber(orders []models.ShootingOrder) []models.ShootingOrder {
	if len(orders) == 0 {
		return orders
	}

	// 按订单号分组
	orderMap := make(map[string][]models.ShootingOrder)
	orderKeys := make([]string, 0) // 保持顺序

	for _, order := range orders {
		if _, exists := orderMap[order.OrderNumber]; !exists {
			orderKeys = append(orderKeys, order.OrderNumber)
		}
		orderMap[order.OrderNumber] = append(orderMap[order.OrderNumber], order)
	}

	// 合并每组订单
	merged := make([]models.ShootingOrder, 0, len(orderKeys))
	for _, orderNum := range orderKeys {
		group := orderMap[orderNum]
		if len(group) == 1 {
			merged = append(merged, group[0])
			continue
		}

		// 合并多行
		mergedOrder := s.mergeOrderGroup(group)
		merged = append(merged, mergedOrder)
	}

	log.Printf("[ExcelParser] 合并完成: %d 行 → %d 条订单", len(orders), len(merged))
	return merged
}

// mergeOrderGroup 合并同一订单号的多行
func (s *ExcelParserService) mergeOrderGroup(orders []models.ShootingOrder) models.ShootingOrder {
	// 基于第一行创建合并结果
	result := orders[0]

	// 收集所有日期和地点
	var entries []dateLocation
	locationSet := make(map[string]bool)     // 去重地点
	photographerSet := make(map[string]bool) // 去重摄影师
	salesSet := make(map[string]bool)        // 去重销售
	consultantSet := make(map[string]bool)   // 去重顾问

	for _, order := range orders {
		entries = append(entries, dateLocation{
			month:    order.ShootMonth,
			day:      order.ShootDay,
			location: order.Location,
		})
		if order.Location != "" {
			locationSet[order.Location] = true
		}
		if order.Photographer != "" {
			photographerSet[order.Photographer] = true
		}
		if order.Sales != "" {
			salesSet[order.Sales] = true
		}
		if order.Consultant != "" {
			consultantSet[order.Consultant] = true
		}
	}

	// 合并日期：按连续性分组
	result.ShootDay = s.mergeDays(entries)

	// 合并地点
	result.Location = s.mergeStringSet(locationSet)

	// 合并人员
	result.Photographer = s.mergeStringSet(photographerSet)
	result.Sales = s.mergeStringSet(salesSet)
	result.Consultant = s.mergeStringSet(consultantSet)

	// 使用第一行的月份和年份
	result.ShootYear = orders[0].ShootYear
	result.ShootMonth = orders[0].ShootMonth

	// 重新计算拍摄日期
	result.ComputeShootDate()

	return result
}

// mergeDays 合并日期，连续的用-，不连续的用+
func (s *ExcelParserService) mergeDays(entries []dateLocation) string {
	if len(entries) == 0 {
		return ""
	}
	if len(entries) == 1 {
		return entries[0].day
	}

	// 提取所有日期数字并排序
	type dayInfo struct {
		dayNum   int
		dayStr   string
		location string
	}
	var days []dayInfo

	for _, e := range entries {
		// 解析日期（可能是 "8" 或 "8-9"）
		dayStr := e.day
		firstDay := s.extractFirstDay(dayStr)
		if firstDay > 0 {
			days = append(days, dayInfo{dayNum: firstDay, dayStr: dayStr, location: e.location})
		}
	}

	// 按日期排序
	sort.Slice(days, func(i, j int) bool {
		return days[i].dayNum < days[j].dayNum
	})

	// 构建合并后的日期字符串
	// 连续的日期范围用 "-"，不连续的用 "+"
	var parts []string
	var rangeStart, rangeEnd int

	for i, d := range days {
		if i == 0 {
			rangeStart = d.dayNum
			rangeEnd = d.dayNum
			continue
		}

		// 检查是否连续（允许差1天）
		if d.dayNum == rangeEnd+1 {
			rangeEnd = d.dayNum
		} else {
			// 保存当前范围
			parts = append(parts, formatDayRange(rangeStart, rangeEnd))
			rangeStart = d.dayNum
			rangeEnd = d.dayNum
		}
	}
	// 保存最后一个范围
	parts = append(parts, formatDayRange(rangeStart, rangeEnd))

	return strings.Join(parts, "+")
}

// formatDayRange 格式化日期范围
func formatDayRange(start, end int) string {
	if start == end {
		return strconv.Itoa(start)
	}
	return strconv.Itoa(start) + "-" + strconv.Itoa(end)
}

// extractFirstDay 从日期字符串提取第一个日期数字
func (s *ExcelParserService) extractFirstDay(dayStr string) int {
	if dayStr == "" {
		return 0
	}
	// 处理 "8-9" 或 "8" 格式
	parts := strings.FieldsFunc(dayStr, func(r rune) bool {
		return r == '-' || r == '、' || r == '+' || r == ','
	})
	if len(parts) > 0 {
		day, _ := strconv.Atoi(strings.TrimSpace(parts[0]))
		return day
	}
	return 0
}

// mergeStringSet 合并字符串集合，用+连接
func (s *ExcelParserService) mergeStringSet(set map[string]bool) string {
	if len(set) == 0 {
		return ""
	}
	var parts []string
	for k := range set {
		if k != "" {
			parts = append(parts, k)
		}
	}
	// 排序以保持一致性
	sort.Strings(parts)
	return strings.Join(parts, "+")
}
