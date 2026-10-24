import Foundation

protocol NeuralSpeechProviding: Sendable {
    func audio(for text: String, language: String, rate: Int) async throws -> Data
    func audio(for text: String, language: String, rate: Int, speaker: LocalChatPersona) async throws -> Data
}
extension NeuralSpeechProviding {
    func audio(for text: String, language: String, rate: Int, speaker: LocalChatPersona) async throws -> Data { try await audio(for:text,language:language,rate:rate) }
}

enum NeuralSpeechError: Error { case invalidText, invalidResponse, tooLarge, noAudio }

/// Only spoken reply text is sent. No transcript history, screen image, cookies
/// from a browser, API key, or development runtime is needed by this transport.
actor EdgeNeuralSpeechService: NeuralSpeechProviding {
    static func voice(for language: String, speaker: LocalChatPersona = .sig) -> String {
        if language.hasPrefix("en") {
            switch speaker {
            case .sig: return "en-US-AndrewNeural"
            case .rita: return "en-US-JennyNeural"
            case .ada: return "en-US-AriaNeural"
            case .gantt: return "en-US-GuyNeural"
            case .elinor: return "en-US-EmmaMultilingualNeural"
            case .toni: return "en-US-EricNeural"
            }
        }
        switch speaker {
        case .sig: return "pt-BR-AntonioNeural"
        case .rita: return "pt-BR-ThalitaMultilingualNeural"
        case .ada: return "en-US-AvaMultilingualNeural"
        case .gantt: return "en-US-BrianMultilingualNeural"
        case .elinor: return "en-US-EmmaMultilingualNeural"
        case .toni: return "en-US-AndrewMultilingualNeural"
        }
    }
    static func ssml(text: String, language: String, rate: Int, speaker: LocalChatPersona = .sig) -> String {
        let clean = String(text.unicodeScalars.filter { $0.value >= 32 || [9, 10, 13].contains($0.value) })
        let escaped = clean.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
        let speed = min(30, max(-40, rate))
        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(language.hasPrefix("en") ? "en-US" : "pt-BR")'><voice name='\(voice(for: language,speaker:speaker))'><prosody pitch='+0Hz' rate='\(speed >= 0 ? "+" : "")\(speed)%' volume='+0%'>\(escaped)</prosody></voice></speak>"
    }
    static func audioPayload(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw NeuralSpeechError.invalidResponse }
        let length = Int(bytes[0]) * 256 + Int(bytes[1])
        guard length > 0, length <= bytes.count - 2,
              let header = String(bytes: bytes[2..<(2 + length)], encoding: .utf8),
              header.components(separatedBy: "\r\n").contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "Path:audio" })
        else { throw NeuralSpeechError.invalidResponse }
        let payload = Data(bytes.dropFirst(2 + length))
        guard header.contains("Content-Type:audio/mpeg") || payload.isEmpty else { throw NeuralSpeechError.invalidResponse }
        return payload
    }

    func audio(for text: String, language: String, rate: Int) async throws -> Data {
        try await audio(for:text,language:language,rate:rate,speaker:.sig)
    }
    func audio(for text: String, language: String, rate: Int, speaker: LocalChatPersona) async throws -> Data {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16_384 else { throw NeuralSpeechError.invalidText }
        // Keep individual frames below the service's size limit, without cutting
        // UTF-8 or an escaped XML entity. Responses normally fit a single turn.
        let chunks = Self.chunks(text)
        var result = Data()
        for chunk in chunks {
            try Task.checkCancellation()
            let part = try await request(chunk, language: language, rate: rate, speaker:speaker)
            guard result.count + part.count <= 4_000_000 else { throw NeuralSpeechError.tooLarge }
            result.append(part)
        }
        return result
    }

    static func chunks(_ text: String) -> [String] {
        var result: [String] = [], current = "", escapedBytes = 0
        for character in text {
            let part = String(character)
            let size = part.utf8.reduce(0) { total, byte in
                total + ([34, 39].contains(byte) ? 6 : byte == 38 ? 5 : [60, 62].contains(byte) ? 4 : 1)
            }
            if escapedBytes + size > 3_000 || current.utf8.count + part.utf8.count > 2_000 {
                if let boundary = current.lastIndex(where: { $0.isWhitespace || ".!?;".contains($0) }), boundary != current.startIndex {
                    let end = current.index(after: boundary)
                    result.append(String(current[..<end]))
                    current = String(current[end...])
                } else { result.append(current); current = "" }
                // The retained suffix is bounded; compute its XML byte cost.
                escapedBytes = current.utf8.reduce(0) { $0 + ([34,39].contains($1) ? 6 : $1 == 38 ? 5 : [60,62].contains($1) ? 4 : 1) }
            }
            current.append(character); escapedBytes += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func request(_ text: String, language: String, rate: Int, speaker: LocalChatPersona) async throws -> Data {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var components = URLComponents(string: "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1")!
        components.queryItems = [URLQueryItem(name: "TrustedClientToken", value: EdgeSpeechToken.client),
            URLQueryItem(name: "ConnectionId", value: id), URLQueryItem(name: "Sec-MS-GEC", value: EdgeSpeechToken.value()),
            URLQueryItem(name: "Sec-MS-GEC-Version", value: "2-155.0.4283.45")]
        var request = URLRequest(url: components.url!, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36 Edg/155.0.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("muid=\(UUID().uuidString.replacingOccurrences(of: "-", with: ""));", forHTTPHeaderField: "Cookie")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 262_144
        socket.resume()
        let deadline = Task {
            try? await Task.sleep(for: .seconds(18))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer { deadline.cancel(); socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
            let timestamp = formatter.string(from: Date())
            let config = #"{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}"#
            try await socket.send(.string("X-Timestamp:\(timestamp)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n\(config)\r\n"))
            try await socket.send(.string("X-RequestId:\(id)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(timestamp)Z\r\nPath:ssml\r\n\r\n\(Self.ssml(text: text, language: language, rate: rate, speaker:speaker))"))
            var audio = Data()
            while true {
                try Task.checkCancellation()
                let message = try await socket.receive()
                switch message {
                case .data(let frame):
                    let payload = try Self.audioPayload(frame)
                    guard audio.count + payload.count <= 4_000_000 else { throw NeuralSpeechError.tooLarge }
                    audio.append(payload)
                case .string(let frame):
                    let headers = frame.components(separatedBy: "\r\n\r\n").first ?? ""
                    if headers.components(separatedBy: "\r\n").contains("Path:turn.end") {
                        guard !audio.isEmpty else { throw NeuralSpeechError.noAudio }
                        return audio
                    }
                @unknown default: throw NeuralSpeechError.invalidResponse
                }
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
    }
}
