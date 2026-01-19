-- Tvtxiu 数据库索引优化
-- 运行: psql -d tvtxiu -f migrations/add_indexes.sql

-- 订单表索引优化
CREATE INDEX IF NOT EXISTS idx_orders_assigned_to ON orders(assigned_to);
CREATE INDEX IF NOT EXISTS idx_orders_is_completed ON orders(is_completed);
CREATE INDEX IF NOT EXISTS idx_orders_is_archived ON orders(is_archived);
CREATE INDEX IF NOT EXISTS idx_orders_final_deadline ON orders(final_deadline);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);

-- 复合索引（常用查询组合）
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(is_completed, is_archived);
CREATE INDEX IF NOT EXISTS idx_orders_assigned_completed ON orders(assigned_to, is_completed);

-- 拍摄订单表索引
CREATE INDEX IF NOT EXISTS idx_shooting_orders_order_number ON shooting_orders(order_number);
CREATE INDEX IF NOT EXISTS idx_shooting_orders_year_month ON shooting_orders(shoot_year, shoot_month);
CREATE INDEX IF NOT EXISTS idx_shooting_orders_matched ON shooting_orders(matched_order_id);
