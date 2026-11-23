import Foundation

private final class GuestRedirectRefusal: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Direct HTTPS guest transport. It has no reference to pairing or Profile credentials.
public protocol DJConnectGuestTransporting: Sendable {
    func send(_ action: DJConnectGuestTransport.Action, body: Data, bearer: String?) async throws -> Data
    func cancel()
}

public final class DJConnectGuestTransport: DJConnectGuestTransporting, @unchecked Sendable {
    public enum Action: String, Sendable {
        case redeem, renew, leave, context, ask, request
        case emotion, artwork
        case requestStatus = "request/status"
    }
    public enum Failure: Error, Sendable { case invalidResponse, unavailable, withdrawn }
    private let origin: URL
    private let session: URLSession

    public init(invitation: DJConnectGuestInvitation) {
        origin = invitation.origin
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false; configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration, delegate: GuestRedirectRefusal(), delegateQueue: nil)
    }

    /// No automatic application retry. In particular a lost redemption never mints again.
    public func send(_ action: Action, body: Data, bearer: String? = nil) async throws -> Data {
        guard body.count <= 8192 else { throw Failure.invalidResponse }
        if action == .redeem {
            guard bearer == nil else { throw Failure.invalidResponse }
        } else {
            guard let bearer, bearer.hasPrefix("djcg_"), bearer.utf8.count <= 256,
                  bearer.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
                throw Failure.invalidResponse
            }
        }
        var request = URLRequest(url: origin.appending(path: "api/djconnect/v1/participation/" + action.rawValue))
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
              response.url?.scheme == "https", response.url?.host == origin.host,
              response.url?.port == origin.port,
              response.expectedContentLength <= (action == .artwork ? 256000 : 65536) else { throw Failure.invalidResponse }
        let media = http.value(forHTTPHeaderField: "Content-Type")?.lowercased().split(separator: ";").first.map(String.init)
        let expectedImage = action == .artwork && http.statusCode == 200
        guard expectedImage ? ["image/jpeg", "image/png", "image/webp"].contains(media ?? "") : media == "application/json" else { throw Failure.invalidResponse }
        let limit = expectedImage ? 256000 : 65536
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw Failure.invalidResponse }
            data.append(byte)
        }
        if [401, 403, 410].contains(http.statusCode) { throw Failure.withdrawn }
        guard http.statusCode == 200 else { throw Failure.unavailable }
        return data
    }

    public func cancel() { session.invalidateAndCancel() }
}
