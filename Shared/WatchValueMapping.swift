import Foundation

public struct WatchValueMapping {
    public static func value(for type: WatchSingleValueType, data: SpectrogramData) -> Float {
        switch type {
        case .laeq:
            return data.levels["LAeq"] ?? data.broadbandLevel
        case .lceq:
            return data.levels["LCeq"] ?? data.broadbandLevel
        case .lzeq:
            return data.levels["LZeq"] ?? data.broadbandLevel
        case .lafMax:
            return data.levels["LAFmax"] ?? data.levels["LAF"] ?? data.broadbandLevel
        case .lafMin:
            return data.levels["LAFmin"] ?? data.levels["LAF"] ?? data.broadbandLevel
        case .lcfMax:
            return data.levels["LCFmax"] ?? data.levels["LCF"] ?? data.broadbandLevel
        case .lcfMin:
            return data.levels["LCFmin"] ?? data.levels["LCF"] ?? data.broadbandLevel
        }
    }
}
