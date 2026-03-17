import Foundation
import CoreFoundation

enum StringDecoding {

    /// 将 GBK/GB18030 编码的 Data 解码为 Swift String
    static func decodeGBK(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let enc = String.Encoding.gb18030,
           let s = String(data: data, encoding: enc) { return s }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

extension String.Encoding {
    /// GB18030 编码（兼容 GBK / GB2312）
    static var gb18030: String.Encoding? {
        let cf = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String.Encoding(rawValue: cf)
    }
}
