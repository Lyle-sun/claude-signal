import Foundation

/// 模型定价（$/M tokens），截至 2026-06-09
/// 未知模型返回 $0，UI 显示"未知模型"警告
public enum ModelPricing {
    /// 单条消息的成本
    public struct Cost {
        public let inputCost: Double
        public let outputCost: Double
        public let cacheReadCost: Double
        public let totalCost: Double

        public init(inputCost: Double, outputCost: Double, cacheReadCost: Double) {
            self.inputCost = inputCost
            self.outputCost = outputCost
            self.cacheReadCost = cacheReadCost
            self.totalCost = inputCost + outputCost + cacheReadCost
        }
    }

    /// 模型定价条目
    private struct PriceEntry {
        let inputPerM: Double    // $/M input tokens
        let outputPerM: Double   // $/M output tokens
        let cacheReadPerM: Double // $/M cache read tokens
    }

    /// 已知模型定价表
    private static let pricingTable: [String: PriceEntry] = [
        // Claude Opus 4
        "claude-opus-4-8": PriceEntry(inputPerM: 15, outputPerM: 75, cacheReadPerM: 1.50),
        "claude-opus-4-7": PriceEntry(inputPerM: 15, outputPerM: 75, cacheReadPerM: 1.50),
        "claude-opus-4-6": PriceEntry(inputPerM: 15, outputPerM: 75, cacheReadPerM: 1.50),
        "claude-opus-4-5": PriceEntry(inputPerM: 15, outputPerM: 75, cacheReadPerM: 1.50),
        "claude-opus-4-0": PriceEntry(inputPerM: 15, outputPerM: 75, cacheReadPerM: 1.50),

        // Claude Sonnet 4
        "claude-sonnet-4-6": PriceEntry(inputPerM: 3, outputPerM: 15, cacheReadPerM: 0.30),
        "claude-sonnet-4-5": PriceEntry(inputPerM: 3, outputPerM: 15, cacheReadPerM: 0.30),
        "claude-sonnet-4-0": PriceEntry(inputPerM: 3, outputPerM: 15, cacheReadPerM: 0.30),

        // Claude Haiku 3.5 / 4.5
        "claude-haiku-4-5": PriceEntry(inputPerM: 0.80, outputPerM: 4, cacheReadPerM: 0.08),
        "claude-3-5-haiku": PriceEntry(inputPerM: 0.80, outputPerM: 4, cacheReadPerM: 0.08),
        "haiku":             PriceEntry(inputPerM: 0.80, outputPerM: 4, cacheReadPerM: 0.08),

        // 常见别名 / 变体
        "claude-sonnet-4-20250514": PriceEntry(inputPerM: 3, outputPerM: 15, cacheReadPerM: 0.30),
        "claude-opus-4-20250115":   PriceEntry(inputPerM: 15, outputPerM: 75, cacheReadPerM: 1.50),

        // GLM-5 (智谱AI) — Input $1.00/M, Output $3.20/M, Cache ~$0.10/M
        "glm-5":   PriceEntry(inputPerM: 1.00, outputPerM: 3.20, cacheReadPerM: 0.10),
        "glm-5.1": PriceEntry(inputPerM: 1.00, outputPerM: 3.20, cacheReadPerM: 0.10),

        // DeepSeek V4-Pro — Input $0.42/M, Output $0.84/M, Cache $0.0035/M (¥3/¥6/¥0.025 per M)
        "deepseek-v4":     PriceEntry(inputPerM: 0.42, outputPerM: 0.84, cacheReadPerM: 0.0035),
        "deepseek-v4-pro": PriceEntry(inputPerM: 0.42, outputPerM: 0.84, cacheReadPerM: 0.0035),
    ]

    /// 计算 token 成本
    /// - Parameters:
    ///   - model: 模型名称（如 "claude-sonnet-4-6"）
    ///   - inputTokens: 输入 token 数
    ///   - outputTokens: 输出 token 数
    ///   - cacheReadTokens: 缓存读取 token 数
    /// - Returns: 成本明细
    public static func calculate(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int
    ) -> Cost {
        // 精确匹配
        if let entry = pricingTable[model] {
            return Cost(
                inputCost: Double(inputTokens) * entry.inputPerM / 1_000_000,
                outputCost: Double(outputTokens) * entry.outputPerM / 1_000_000,
                cacheReadCost: Double(cacheReadTokens) * entry.cacheReadPerM / 1_000_000
            )
        }

        // 前缀匹配（处理版本号后缀，如 claude-sonnet-4-6-20250514）
        for (key, entry) in pricingTable where model.hasPrefix(key) {
            return Cost(
                inputCost: Double(inputTokens) * entry.inputPerM / 1_000_000,
                outputCost: Double(outputTokens) * entry.outputPerM / 1_000_000,
                cacheReadCost: Double(cacheReadTokens) * entry.cacheReadPerM / 1_000_000
            )
        }

        // 未知模型：成本 $0
        return Cost(inputCost: 0, outputCost: 0, cacheReadCost: 0)
    }

    /// 是否为已知模型
    public static func isKnownModel(_ model: String) -> Bool {
        if pricingTable[model] != nil { return true }
        for key in pricingTable.keys where model.hasPrefix(key) { return true }
        return false
    }

    /// 是否为合成消息（无真实 token，如 <synthetic>）
    public static func isSyntheticModel(_ model: String) -> Bool {
        model == "<synthetic>"
    }
}
