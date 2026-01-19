package main

import (
	"fmt"

	"github.com/xuri/excelize/v2"
)

func main() {
	f, err := excelize.OpenFile("/Users/dundun/Desktop/apps/Tvtxiu/订单信息.xlsx")
	if err != nil {
		fmt.Printf("错误: %v\n", err)
		return
	}
	defer f.Close()

	sheets := []string{"2025年拍摄订单", "2026年拍摄订单"}

	for _, sheetName := range sheets {
		rows, err := f.GetRows(sheetName)
		if err != nil {
			fmt.Printf("读取 %s 失败: %v\n", sheetName, err)
			continue
		}

		fmt.Printf("\n========== %s ==========\n", sheetName)

		if len(rows) > 0 {
			fmt.Println("\n=== 第一行 ===")
			for i, cell := range rows[0] {
				if cell != "" {
					fmt.Printf("[%d] '%s'\n", i, cell)
				}
			}
		}

		if len(rows) > 1 {
			fmt.Println("\n=== 第二行 ===")
			for i, cell := range rows[1] {
				if cell != "" {
					fmt.Printf("[%d] '%s'\n", i, cell)
				}
			}
		}

		if len(rows) > 2 {
			fmt.Println("\n=== 第三行 ===")
			for i, cell := range rows[2] {
				if cell != "" {
					fmt.Printf("[%d] '%s'\n", i, cell)
				}
			}
		}
	}
}
