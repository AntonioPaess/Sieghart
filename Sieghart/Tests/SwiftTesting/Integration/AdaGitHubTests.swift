import Foundation
import Testing

private let integrationGitHubToken = "github_pat_" + String(repeating: "x", count: 64)

extension MacContractsTests {
    @Suite(.tags(.localChat, .isolated)) @MainActor struct AdaGitHubRestoreTests {
        @Test("G18.07 — construção sem load, restore uma vez ao abrir Ada e disconnect impede restauração")
        func restoresOnlyOnOpen() async throws {
            let credentials = IntegrationGitHubCredentials(token: integrationGitHubToken)
            let transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses())
            let connection = AdaGitHubViewModel(service: AdaGitHubContext(transport: transport, credentials: credentials))
            let chat = LocalChatViewModel(generator: UnavailableLocalChatEngine(), github: connection)
            defer { chat.shutdown() }
            #expect(await credentials.loads == 0)
            #expect(!connection.status.connected)
            await chat.prepare(); await chat.prepare()
            #expect(connection.status.connected && connection.status.login == "fixture-user")
            #expect(await credentials.loads == 1)
            let count = await transport.requests.count
            #expect(count == 1)
            await connection.disconnect(); await chat.prepare()
            #expect(!connection.status.connected)
            #expect(await transport.requests.count == count)
        }
    }
    @Suite(.tags(.localChat, .isolated)) struct AdaGitHubConnectionTests {
        @Test("G18.08 — desconectado não requisita; restore sem credencial é idempotente")
        func disconnectedAndRestore() async throws {
            let credentials = IntegrationGitHubCredentials(), transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses())
            let context = AdaGitHubContext(transport: transport, credentials: credentials)
            let initial = await context.status()
            #expect(!initial.connected && initial.snapshot == nil)
            #expect(await credentials.loads == 0)
            #expect(await transport.requests.isEmpty)
            #expect(await context.answer().contains("Connect GitHub"))
            try await context.restore(); try await context.restore()
            #expect(await credentials.loads == 1)
            #expect(await transport.requests.isEmpty)
        }
        @Test("G18.08 — tokens inválidos não entram no transporte", arguments: ["", "short", integrationGitHubToken + "\n", "bearer " + integrationGitHubToken, "https://github.com/token", String(repeating: "x", count: 256)])
        func invalidToken(_ token: String) async throws {
            let credentials = IntegrationGitHubCredentials(), transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses())
            let context = AdaGitHubContext(transport: transport, credentials: credentials)
            await #expect(throws: AdaGitHubError.invalidToken) { try await context.connect(token: token) }
            #expect(await transport.requests.isEmpty)
            #expect(await credentials.saves == 0)
        }
        @Test("G18.08 — snapshot limitado, CI, cache TTL e requests read-only autenticados")
        func snapshotAndCache() async throws {
            let token = integrationGitHubToken
            let credentials = IntegrationGitHubCredentials(), transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses()), clock = IntegrationGitHubClock()
            let context = AdaGitHubContext(transport: transport, credentials: credentials, now: { clock.now() })
            try await context.connect(token: token)
            let connected = await context.status()
            #expect(connected.connected && connected.login == "fixture-user" && connected.snapshot == nil)
            #expect(await credentials.token == token)
            try await context.refresh()
            let ready = await context.status()
            #expect(ready.snapshot?.repositoryCount == 5 && ready.snapshot?.stars == 42)
            #expect(ready.snapshot?.myPRs.first?.ci == "failure" && ready.snapshot?.reviewCount == 1)
            #expect(ready.snapshot?.defaultBranchCI.first?.ci == "success")
            let answer = await context.answer()
            #expect(await transport.requests.count == 4)
            #expect(answer.contains("fixture-user") && answer.contains("owner/project#7"))
            #expect(answer.contains("failure") && answer.contains("maximum 100") && !answer.contains(token))
            #expect(answer.utf8.count <= AdaGitHubContext.maximumOutputBytes)
            let ci = await context.answer(topic: "ci")
            #expect(ci.contains("Default-branch CI") && !ci.contains("Stars:"))
            clock.advance(); _ = await context.answer()
            #expect(await transport.requests.count == 7)
            _ = await context.answer(topic: "edit_code")
            let requests = await transport.requests
            #expect(requests.count == 7)
            for request in requests {
                let url = try #require(request.url)
                #expect(url.host == "api.github.com" && url.scheme == "https")
                #expect(["/user", "/user/repos", "/graphql"].contains(url.path))
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
                if url.path == "/graphql" {
                    #expect(request.httpMethod == "POST")
                    let data = try #require(request.httpBody)
                    let body = try #require(String(data: data, encoding: .utf8))
                    #expect(body.contains("query") && !body.contains("mutation") && !body.contains(token))
                } else { #expect(request.httpMethod == "GET" && request.httpBody == nil) }
            }
            try await context.disconnect()
            let empty = await context.status()
            #expect(!empty.connected && empty.login == nil && empty.snapshot == nil)
            #expect(await credentials.token == nil)
            _ = await context.answer()
            #expect(await transport.requests.count == requests.count)
        }
        @Test("G18.08 — credencial salva restaura sem regravar")
        func restoresWithoutSavingAgain() async throws {
            let credentials = IntegrationGitHubCredentials(token: integrationGitHubToken)
            let context = AdaGitHubContext(transport: IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses()), credentials: credentials)
            #expect(await credentials.loads == 0)
            try await context.restore()
            #expect(await context.status().connected)
            #expect(await credentials.loads == 1)
            #expect(await credentials.saves == 0)
        }
    }
    @Suite(.tags(.localChat, .isolated)) struct AdaGitHubErrorTests {
        @Test("G18.09 — códigos HTTP recusados não salvam credencial", arguments: [302, 401, 429])
        func rejectedStatus(_ status: Int) async throws {
            let credentials = IntegrationGitHubCredentials(), transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses())
            await transport.set(status: status)
            let context = AdaGitHubContext(transport: transport, credentials: credentials)
            let expected: AdaGitHubError = status == 302 ? .redirectDenied : status == 401 ? .accessUnavailable : .rateLimited
            await #expect(throws: expected) { try await context.connect(token: integrationGitHubToken) }
            #expect(await credentials.saves == 0)
            #expect(await context.status().connected == false)
        }
        @Test("G18.09 — redirect e scheme inesperados são recusados", arguments: ["https://evil.example/user", "http://api.github.com/user"])
        func rejectsRedirect(_ target: String) async throws {
            let transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses())
            await transport.set(status: 200, redirectedURL: try #require(URL(string: target)))
            let context = AdaGitHubContext(transport: transport, credentials: IntegrationGitHubCredentials())
            await #expect(throws: AdaGitHubError.redirectDenied) { try await context.connect(token: integrationGitHubToken) }
        }
        @Test("G18.09 — body excessivo e JSON inválido são recusados", arguments: [true, false])
        func rejectsInvalidBody(_ tooLarge: Bool) async throws {
            let transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses()), credentials = IntegrationGitHubCredentials()
            await transport.set(data: tooLarge ? Data(repeating: 120, count: 131_073) : Data("not json".utf8), for: "/user")
            let context = AdaGitHubContext(transport: transport, credentials: credentials)
            await #expect(throws: tooLarge ? AdaGitHubError.responseTooLarge : AdaGitHubError.invalidResponse) { try await context.connect(token: integrationGitHubToken) }
            #expect(await credentials.saves == 0)
            #expect(await context.status().connected == false)
        }
        @Test("G18.09 — primeiro refresh falho não cria snapshot nem expõe token; título grande permanece bounded")
        func failedRefreshAndBoundedTitle() async throws {
            let transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses())
            let context = AdaGitHubContext(transport: transport, credentials: IntegrationGitHubCredentials())
            try await context.connect(token: integrationGitHubToken)
            await transport.set(data: try IntegrationGitHubPayloads.json(["data": ["viewer": ["login": "other-user"]]]), for: "/graphql")
            await #expect(throws: AdaGitHubError.invalidResponse) { try await context.refresh() }
            let failed = await context.status()
            #expect(failed.snapshot == nil && !failed.detail.contains(integrationGitHubToken))
            let large = try IntegrationGitHubPayloads.pulse(title: String(repeating: "🌱", count: 10_000))
            #expect(large.count < 131_072)
            await transport.set(data: large, for: "/graphql"); try await context.refresh()
            #expect(await context.answer().utf8.count <= AdaGitHubContext.maximumOutputBytes)
        }
    }
    @Suite(.tags(.localChat, .isolated)) @MainActor struct AdaGitHubCancellationTests {
        @Test("G18.10 — cancelar connect não salva credencial")
        func cancelConnect() async throws {
            let credentials = IntegrationGitHubCredentials(), transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses())
            let context = AdaGitHubContext(transport: transport, credentials: credentials)
            await transport.setPaused(true)
            let task = Task { try await context.connect(token: integrationGitHubToken) }
            do {
            try await IntegrationWait.untilAsync { await transport.waiting.count == 1 }
            task.cancel(); await transport.release()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(await credentials.saves == 0)
            } catch {
                task.cancel(); await transport.release(); _ = try? await task.value
                throw error
            }
        }
        @Test("G18.10 — busy bloqueia concorrência e disconnect invalida resposta atrasada")
        func disconnectDuringRefresh() async throws {
            let credentials = IntegrationGitHubCredentials(), transport = IntegrationGitHubTransport(responses: try IntegrationGitHubPayloads.responses())
            let context = AdaGitHubContext(transport: transport, credentials: credentials)
            try await context.connect(token: integrationGitHubToken)
            await transport.setPaused(true)
            let task = Task { try await context.refresh() }
            do {
            try await IntegrationWait.untilAsync { await transport.waiting.count == 1 }
            await #expect(throws: AdaGitHubError.busy) { try await context.refresh() }
            try await context.disconnect(); await transport.release()
            do { try await task.value; Issue.record("Disconnected request restored data") }
            catch { #expect(error is CancellationError || error as? AdaGitHubError == .superseded) }
            let final = await context.status()
            #expect(!final.connected && final.snapshot == nil)
            #expect(await credentials.token == nil)
            } catch {
                task.cancel(); await transport.release(); _ = try? await task.value
                throw error
            }
        }
    }
}
