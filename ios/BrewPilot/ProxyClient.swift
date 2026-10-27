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

    /// Production proxy on Modal. For local dev, point at your Mac's LAN IP
    /// (`uvicorn server.app:app`, same Wi-Fi) or 127.0.0.1 on the simulator.
    var baseURL = URL(string: "https://fmsuban--brewpilot-proxy-web.us-east.modal.run")!

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

    // TODO(day 5): postVision(frame:context:) multipart -> VisionResult.
    // TODO(day 6): postSegment(frame:) -> mask.
    // TODO(day 5): postReport(timeline:observations:) -> bullets + tip.
}
