import Foundation

final class DataService {

    // MARK: - 新浪财经（A股 + 美股）

    static func fetchSinaQuotes(codes: [String]) async throws -> [String: Quote] {
        guard !codes.isEmpty else { return [:] }
        let escaped = codes
            .map { $0.lowercased().replacingOccurrences(of: ".", with: "$") }
            .joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(escaped)") else { return [:] }
        var req = URLRequest(url: url)
        req.setValue("http://finance.sina.com.cn/", forHTTPHeaderField: "Referer")
        let (data, _) = try await URLSession.shared.data(for: req)
        return parseSinaResponse(StringDecoding.decodeGBK(data))
    }

    /// 解析新浪接口响应字符串（抽出供单元测试使用）
    static func parseSinaResponse(_ body: String) -> [String: Quote] {
        var result: [String: Quote] = [:]
        for line in body.components(separatedBy: ";\n") where line.contains("hq_str_") {
            guard let codeRange  = line.range(of: "hq_str_"),
                  let equalsRange = line.range(of: "=\"") else { continue }
            let code = String(line[codeRange.upperBound..<equalsRange.lowerBound])
                .replacingOccurrences(of: "$", with: ".")

            guard let valStart = line.range(of: "=\""),
                  let valEnd   = line.lastIndex(of: "\""),
                  valEnd > valStart.upperBound else { continue }
            let params = String(line[valStart.upperBound..<valEnd])
                .components(separatedBy: ",")

            guard params.count > 1, !params[0].isEmpty else { continue }

            let quote: Quote?
            if code.hasPrefix("sh") || code.hasPrefix("sz") || code.hasPrefix("bj") {
                quote = parseAStock(code: code, params: params)
            } else if code.hasPrefix("usr_") {
                quote = parseUSStock(code: code, params: params)
            } else {
                continue
            }
            if let q = quote { result[code] = q }
        }
        return result
    }

    // A股字段: 0=名称, 1=今开, 2=昨收, 3=现价, ..., 30=日期, 31=时间
    private static func parseAStock(code: String, params: [String]) -> Quote? {
        guard params.count >= 32 else { return nil }
        let yestClose = Double(params[2]) ?? 0
        let price     = Double(params[3]) ?? 0
        guard price > 0, yestClose > 0 else { return nil }
        let change        = price - yestClose
        let changePercent = change / yestClose * 100
        let updateTime    = "\(params[30]) \(params[31])".trimmingCharacters(in: .whitespaces)
        return Quote(code: code, name: params[0], price: price, change: change,
                     changePercent: changePercent, updateTime: updateTime)
    }

    // 美股字段: 0=名称, 1=现价, 2=涨跌%, 3=更新时间, 4=涨跌额, ..., 21=盘外价, 26=昨收
    private static func parseUSStock(code: String, params: [String]) -> Quote? {
        guard params.count >= 27 else { return nil }
        let yestClose = Double(params[26]) ?? 0
        let rawPrice  = Double(params[1])  ?? 0
        let extPrice  = params.count > 21 ? (Double(params[21]) ?? 0) : 0
        // 主价格为 0 时（夜盘初期），用盘外价格兜底
        let price = rawPrice > 0 ? rawPrice : extPrice
        guard price > 0, yestClose > 0 else { return nil }
        let change        = price - yestClose
        let changePercent = change / yestClose * 100
        return Quote(code: code, name: params[0], price: price, change: change,
                     changePercent: changePercent, updateTime: params[3],
                     extendedPrice: extPrice > 0 ? extPrice : nil)
    }

    // MARK: - 腾讯证券（港股）

    static func fetchTencentHKQuotes(codes: [String]) async throws -> [String: Quote] {
        guard !codes.isEmpty else { return [:] }
        // 腾讯接口使用小写，如 r_hk03690；大写会导致响应变成 v_r_HK03690 无法匹配
        let codeStr = codes.map { "r_\($0)" }.joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(codeStr)") else { return [:] }
        let (data, _) = try await URLSession.shared.data(from: url)
        return parseTencentResponse(StringDecoding.decodeGBK(data))
    }

    // MARK: - Yahoo Finance（韩股）

    /// 从 Yahoo `/v8/finance/chart/<symbol>` 响应 meta 段解析 Quote。
    /// 接口对每只股票各请求一次（v7 batch quote 已被 Yahoo 401 封禁）。
    static func parseKoreanChartMeta(_ data: Data, id: String) -> Quote? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let meta = result["meta"] as? [String: Any] else { return nil }

        let price    = (meta["regularMarketPrice"] as? Double) ?? 0
        let prev     = (meta["chartPreviousClose"] as? Double)
                    ?? (meta["previousClose"]     as? Double) ?? 0
        guard price > 0, prev > 0 else { return nil }

        let change = price - prev
        let pct    = change / prev * 100
        let updateTime: String = {
            guard let ts = meta["regularMarketTime"] as? Double, ts > 0 else { return "" }
            let fmt = DateFormatter()
            fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return fmt.string(from: Date(timeIntervalSince1970: ts))
        }()

        return Quote(code: id, name: "", price: price, change: change,
                     changePercent: pct, updateTime: updateTime)
    }

    /// 并发拉取韩股报价。`ids` 为 Stockbar 内部 ID（如 `kr_005930.ks`）。
    /// 单只失败不影响其它；返回成功解析的 quotes 字典。
    static func fetchKoreanQuotes(ids: [String]) async -> [String: Quote] {
        guard !ids.isEmpty else { return [:] }
        return await withTaskGroup(of: (String, Quote?).self) { group in
            for id in ids {
                guard let symbol = KoreanStockID.toYahooSymbol(id) else { continue }
                group.addTask {
                    guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1m&range=1d") else {
                        return (id, nil)
                    }
                    var req = URLRequest(url: url)
                    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    guard let (data, _) = try? await URLSession.shared.data(for: req) else {
                        return (id, nil)
                    }
                    return (id, parseKoreanChartMeta(data, id: id))
                }
            }
            var out: [String: Quote] = [:]
            for await (id, q) in group {
                if let q { out[id] = q }
            }
            return out
        }
    }

    // MARK: - 腾讯证券（港股）— parseTencentResponse 入口

    /// 解析腾讯港股响应字符串
    static func parseTencentResponse(_ body: String) -> [String: Quote] {
        var result: [String: Quote] = [:]
        for line in body.components(separatedBy: ";\n") where line.contains("v_r_hk") {
            guard let codeRange  = line.range(of: "v_r_hk"),
                  let equalsRange = line.range(of: "=\"") else { continue }
            let rawCode = String(line[codeRange.lowerBound..<equalsRange.lowerBound])
                .replacingOccurrences(of: "v_r_", with: "")
                .lowercased()   // hk00700

            guard let valStart = line.range(of: "=\""),
                  let valEnd   = line.lastIndex(of: "\""),
                  valEnd > valStart.upperBound else { continue }
            let fields = String(line[valStart.upperBound..<valEnd])
                .components(separatedBy: "~")

            // fields: 0=market, 1=名称, 2=code, 3=现价, 4=昨收, ..., 29=成交量, 30=更新时间
            guard fields.count > 30,
                  let price     = Double(fields[3]),
                  let yestClose = Double(fields[4]),
                  price > 0, yestClose > 0 else { continue }
            let change        = price - yestClose
            let changePercent = change / yestClose * 100
            result[rawCode] = Quote(code: rawCode, name: fields[1], price: price, change: change,
                                    changePercent: changePercent, updateTime: fields[30])
        }
        return result
    }
}
