import Foundation

// HTTPS client for the Modal proxy. Never holds the Meta API key.
// Every call validates JSON; on any failure the caller uses local fallback.

enum ProxyError: Error {
    case badResponse
    case decoding(Error)
    case transport(Error)
}

final class ProxyClient {
    static let shared = ProxyClient()

    /// Local proxy on the Mac (`uvicorn server.app:app --host 0.0.0.0`, same
    /// Wi-Fi) via the `-proxyURL http://<mac-ip>:8000` launch argument or the
    /// `proxyURL` default; otherwise the Modal deployment.
    var baseURL = UserDefaults.standard.string(forKey: "proxyURL").flatMap(URL.init(string:))
        ?? URL(string: "https://fmsuban--brewpilot-proxy-web.us-east.modal.run")!

    private let session = URLSession.shared
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    struct Envelope<T: Decodable>: Decodable {
        var source: String
        var recipe: T?
    }

    func fetchRecipe(roast: String, cups: Int, strength: String) async throws -> Recipe {
        struct Body: Encodable { var roast: String; var cups: Int; var strength: String }
        var req = URLRequest(url: baseURL.appendingPathComponent("/recipe"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(roast: roast, cups: cups, strength: strength))
        let (data, _) = try await session.data(for: req)
        do {
            struct RecipeEnvelope: Decodable { var source: String; var recipe: Recipe }
            return try decoder.decode(RecipeEnvelope.self, from: data).recipe
        } catch {
            throw ProxyError.decoding(error)
        }
    }

    /// Wake the Modal container so the first vision check skips a cold start.
    func warmUp() {
        let url = baseURL.appendingPathComponent("/health")
        Task { _ = try? await session.data(from: url) }
    }

    /// One frame + step context -> Muse Wonder observation. Wonder takes
    /// 6-13 s per frame, so 20 s; late coaching still carries its step label.
    func postVision(frame: Data, context: VisionContext) async throws -> (source: String, vision: VisionResult) {
        let boundary = "BrewPilot-\(UUID().uuidString)"
        var req = URLRequest(url: baseURL.appendingPathComponent("/vision"), timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var body = Data()
        func part(_ name: String, filename: String? = nil, type: String? = nil, _ data: Data) {
            var head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\""
            if let filename { head += "; filename=\"\(filename)\"" }
            head += "\r\n"
            if let type { head += "Content-Type: \(type)\r\n" }
            body.append(Data((head + "\r\n").utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        part("context", try encoder.encode(context))
        part("frame", filename: "frame.jpg", type: "image/jpeg", frame)
        body.append(Data("--\(boundary)--\r\n".utf8))

        let reply: (Data, URLResponse)
        do {
            reply = try await session.upload(for: req, from: body)
        } catch {
            throw ProxyError.transport(error)
        }
        let (data, response) = reply
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ProxyError.badResponse }
        do {
            struct VisionEnvelope: Decodable { var source: String; var vision: VisionResult }
            let envelope = try decoder.decode(VisionEnvelope.self, from: data)
            return (envelope.source, envelope.vision)
        } catch {
            throw ProxyError.decoding(error)
        }
    }

    // TODO(day 6): postSegment(frame:) -> mask.
    // TODO(day 6): postReport(timeline:observations:) -> bullets + tip.
}
