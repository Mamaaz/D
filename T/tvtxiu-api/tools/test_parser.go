package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"tvtxiu-api/services"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("用法: go run tools/test_parser.go <excel文件路径> [年份1] [年份2] ...")
		fmt.Println("示例: go run tools/test_parser.go ~/Desktop/订单信息.xlsx 2024 2025 2026")
		os.Exit(1)
	}

	filePath := os.Args[1]

	// 解析目标年份
	var targetYears []int
	for i := 2; i < len(os.Args); i++ {
		var year int
		if _, err := fmt.Sscanf(os.Args[i], "%d", &year); err == nil {
			targetYears = append(targetYears, year)
		}
	}

	log.Printf("开始解析文件: %s", filePath)
	if len(targetYears) > 0 {
		log.Printf("目标年份: %v", targetYears)
	} else {
		log.Printf("解析所有年份")
	}

	parser := services.NewExcelParserService()
	result, err := parser.ParseExcelFile(filePath, targetYears)
	if err != nil {
		log.Fatalf("解析失败: %v", err)
	}

	// 打印统计结果
	fmt.Println("\n========== 解析结果 ==========")
	fmt.Printf("总行数:   %d\n", result.TotalRows)
	fmt.Printf("有效行数: %d\n", result.ValidRows)
	fmt.Printf("跳过行数: %d\n", result.SkippedRows)
	fmt.Printf("订单总数: %d\n", len(result.Orders))

	fmt.Println("\n按年份统计:")
	for year, count := range result.ByYear {
		fmt.Printf("  %d年: %d 条\n", year, count)
	}

	if len(result.Errors) > 0 {
		fmt.Println("\n错误信息:")
		for _, err := range result.Errors {
			fmt.Printf("  - %s\n", err)
		}
	}

	// 打印前5条订单数据
	fmt.Println("\n========== 示例数据 (前5条) ==========")
	showCount := 5
	if len(result.Orders) < showCount {
		showCount = len(result.Orders)
	}
	for i := 0; i < showCount; i++ {
		order := result.Orders[i]
		fmt.Printf("\n[%d] 订单编号: %s\n", i+1, order.OrderNumber)
		fmt.Printf("    日期: %d年%d月%s日\n", order.ShootYear, order.ShootMonth, order.ShootDay)
		fmt.Printf("    地点: %s (%s)\n", order.Location, order.Country)
		fmt.Printf("    类型: %s\n", order.OrderType)
		fmt.Printf("    摄影: %s | 顾问: %s | 销售: %s\n", order.Photographer, order.Consultant, order.Sales)
		if order.ShootDate != nil {
			fmt.Printf("    计算日期: %s\n", order.ShootDate.Format("2006-01-02"))
		}
	}

	// 输出完整 JSON 到文件
	outputPath := "/tmp/parsed_orders.json"
	jsonData, _ := json.MarshalIndent(result, "", "  ")
	os.WriteFile(outputPath, jsonData, 0644)
	fmt.Printf("\n完整结果已保存到: %s\n", outputPath)
}
