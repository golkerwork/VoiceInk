import Foundation

/// Loads or unloads a local Ollama model ahead of time. A cold model takes seconds to load,
/// so dictation loads it while the user is still talking instead of when the text is ready.
enum OllamaWarmup {
    /// How long Ollama keeps the model in memory after a dictation starts.
    private static let keepAlive = "10m"

    static func load(model: String) {
        send(model: model, keepAlive: keepAlive)
    }

    static func unload(model: String) {
        send(model: model, keepAlive: 0)
    }

    /// A request with a model and no prompt only loads (or, with keep_alive 0, unloads) the model.
    private static func send(model: String, keepAlive: Any) {
        let baseURL = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? OllamaService.defaultBaseURL
        guard !model.isEmpty, let url = URL(string: baseURL)?.appendingPathComponent("api/generate") else { return }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": keepAlive])
        URLSession.shared.dataTask(with: request).resume()
    }
}
