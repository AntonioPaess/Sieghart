import AppKit
import Foundation
import Testing
import CoreText

extension LogicTests {
    @Suite(.tags(.logic, .interactions)) struct ProductRecoveryLogicTests {
        @Test("G30.02 · Weather accepts global unqualified names, English and contextual follow-ups")
        func locationPhrasing() {
            for (question, city) in [("Qual a temperatura de Alasca?", "alasca"), ("Sieg, como está o tempo em Zermmat?", "zermmat"), ("What's the temperature in Tokyo?", "tokyo"), ("Está chovendo em Porto?", "porto")] {
                #expect(VoiceWeatherQuery.parse(question)?.city == city)
            }
            #expect(VoiceWeatherQuery.parse("E em Lisboa?", previousCity: "Porto")?.city == "lisboa")
            #expect(VoiceWeatherQuery.parse("Está chovendo lá?", previousCity: "Porto")?.city == "Porto")
            #expect(VoiceWeatherQuery.parse("Alasca", expectsLocation: true)?.city == "alasca")
            #expect(VoiceWeatherQuery.parse("E Zermmat", previousCity: "Porto")?.city == "zermmat")
            #expect(VoiceWeatherQuery.parse("obrigado", previousCity: "Porto") == nil)
            #expect(VoiceWeatherQuery.parse("Explique o que é chuva") == nil)
        }
        @Test("G30.02 · Geographic spelling repair is general and rejects equally close places")
        func spelling() {
            let a = WeatherPlace(name: "Zermatt", latitude: 46, longitude: 7, admin1: "Valais", country: "Switzerland", feature_code: "PPL")
            let b = WeatherPlace(name: "Zermatt", latitude: 10, longitude: 10, admin1: "Other", country: "Other", feature_code: "PPL")
            #expect(WeatherNameMatching.distance("Zermmat", "Zermatt") == 2)
            #expect(WeatherNameMatching.closest("Zermmat", among: [a]) == a)
            #expect(WeatherNameMatching.closest("Zermmat", among: [a,b]) == nil)
            #expect(WeatherNameMatching.closest("unrelated", among: [a]) == nil)
        }
        @Test("G30.02 · Seven distinct weather scenes follow data rather than city names")
        func weatherScenes() {
            for (temperature, code, expected) in [(-4.0, 0, CompanionWeatherMood.frozen), (8, 0, .cold), (22, 0, .comfortable), (32, 0, .hot), (22, 61, .rain), (2, 71, .snow), (22, 95, .storm)] {
                let observation = VoiceWeatherObservation(location: "Any named place", temperature: temperature, feelsLike: temperature, date: Date(), timezone: "UTC", code: code, isDay: true)
                #expect(CompanionWeatherMood.resolve(observation) == expected)
            }
        }
        @Test("G30.02 · Region searches preserve regional scope and source while making audio concise")
        func regionalWeather() async throws {
            let service = VoiceWeatherService(transport: { request in
                let url = try #require(request.url)
                let data = url.host == "geocoding-api.open-meteo.com" ? #"{"results":[{"name":"Alasca","latitude":64.0,"longitude":-152.0,"country":"Estados Unidos","feature_code":"ADM1"}]}"# : #"{"timezone":"America/Anchorage","current":{"time":1800000000,"temperature_2m":-4,"apparent_temperature":-9,"weather_code":71,"is_day":1}}"#
                return (Data(data.utf8), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            }, now: { Date(timeIntervalSince1970: 1800000000) })
            let report = try await service.report(to: .init(city: "alasca", future: false), language: "pt-BR")
            #expect(report.observation?.regionEstimate == true)
            #expect(report.reply.contains("Open-Meteo") && report.reply.contains("horário local"))
            #expect(report.spokenReply(language: "pt-BR").count < report.reply.count)
            #expect(report.spokenReply(language: "pt-BR").contains("referência regional"))
        }
        @Test("G30.03 · Canvas revisions preserve ids, relationships and unrelated labels")
        func revisions() throws {
            let graph = CanvasDiagram(arrangement: .flow, nodes: [.init(id: "a", title: "Entrada", detail: "", kind: .process), .init(id: "b", title: "Saída", detail: "", kind: .terminal)], links: [.init(from: "a", to: "b", label: "")])
            let original = GeneratedCanvas(title: "Test", spokenSummary: "Test graph", code: "", codeLanguage: "", elements: [], diagram: graph)
            let revised = try #require(CanvasRevision.parse("Troque a legenda \"Entrada\" por \"Início\"" )).applying(to: original)
            #expect(revised.id == original.id && revised.diagram?.links == graph.links)
            #expect(revised.diagram?.nodes[0].title == "Início" && revised.diagram?.nodes[1] == graph.nodes[1])
            let highlight = try #require(CanvasRevision.parse("Destaca \"Saída\"" )).applying(to: revised)
            #expect(highlight.diagram?.nodes[1].emphasized == true)
            #expect(CanvasRevision.parse("Não renomeie \"Entrada\" para \"Outra\"") == nil)
            #expect(throws: CanvasRevisionError.self) { try CanvasRevision.rename("Missing", "X").applying(to: original) }
            let svg = CanvasSVGExporter.render(graph, title: "<script>alert('x')</script>")
            #expect(!svg.contains("<script>") && svg.contains("&lt;script&gt;") && svg.contains("marker-end"))
        }
        @Test("G30.01 · Voice address repair never rewrites references to Siri inside the request")
        func address() {
            #expect(VoiceAddressNormalization.request("Siri, leia minha tela") == "Sieg, leia minha tela")
            #expect(VoiceAddressNormalization.request("Explique como funciona a Siri") == "Explique como funciona a Siri")
            #expect(VoiceAddressNormalization.request("Siri funciona offline?") == "Siri funciona offline?")
        }
        @Test("G30.03 · Class diagram requests retain the observed code as data without changing intent")
        func contextualClassDiagram() throws {
            var request = try #require(CanvasRequest.parse("Faça um diagrama dessa classe do CarPlay e me explique"))
            #expect(request.wantsDiagram && !request.wantsCode && request.needsScreenContext)
            request.screenContext = "class DestinationController { func refresh() {} }"
            #expect(request.authorPrompt.contains("DestinationController") && request.authorPrompt.contains("untrusted data"))
            #expect(request.prompt == "Faça um diagrama dessa classe do CarPlay e me explique")
            #expect(CanvasRequest.parse("Crie um diagrama do ciclo da água")?.needsScreenContext == false)
            #expect(CanvasRequest.parse("Escreva o código do Two Sum na minha tela")?.needsScreenContext == false)
        }
        @Test("G30.03 · Observed class members produce connected containment without invented calls")
        func observedClassStructure() throws {
            let source = "final class TripPreviewCoordinator { func showPreview() {} func cancelPreview() {} }"
            let members = [ObservedClassDiagram.Member(identifier: "showPreview", detail: "Shows the selected trip"), .init(identifier: "cancelPreview", detail: "Clears the preview")]
            let canvas = try ObservedClassDiagram.make(title: "Class", summary: "The observed members.", className: "TripPreviewCoordinator", members: members, observed: source)
            let graph = try #require(canvas.diagram)
            #expect(graph.arrangement == .hierarchy && graph.nodes.count == 3)
            #expect(graph.links.allSatisfy { $0.from == "class" })
            #expect(throws: SpatialContentError.self) {
                try ObservedClassDiagram.make(title: "Class", summary: "Missing", className: "TripPreviewCoordinator", members: [.init(identifier: "inventedAPI", detail: ""), members[0]], observed: source)
            }
            #expect(throws: SpatialContentError.self) {
                try ObservedClassDiagram.make(title: "Class", summary: "Wrong root", className: "showPreview", members: members, observed: source)
            }
        }
    }
}

extension MacContractsTests {
    @MainActor @Suite(.tags(.isolated, .voiceIntegration)) struct ProductRecoveryStateTests {
        @Test("G30.04 · Artifact files survive reopening and cannot turn into executable SVG markup")
        func artifactStorage() throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-library-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let library = CompanionArtifactLibrary(directory: root)
            let canvas = GeneratedCanvas(title: "Example code", spokenSummary: "Display only", code: "print(1)", codeLanguage: "python", elements: [])
            library.saveCanvas(canvas); library.saveCanvas(canvas)
            #expect(library.items.count == 1)
            let item = try #require(library.items.first), url = try #require(library.url(for: item))
            let code = try String(contentsOf: url, encoding: .utf8)
            #expect(url.pathExtension == "py" && code == "print(1)")
            let restored = CompanionArtifactLibrary(directory: root)
            #expect(restored.items == library.items)
            try Data("corrupt".utf8).write(to: root.appendingPathComponent("index.json"))
            let corrupt = CompanionArtifactLibrary(directory: root); corrupt.saveCanvas(canvas)
            let preserved = try String(contentsOf: root.appendingPathComponent("index.json"), encoding: .utf8)
            #expect(corrupt.issue != nil && preserved == "corrupt")
        }
        @Test("G30.03 · Fifteen-step walkthrough checkpoints survive restart at the completed offset")
        func checkpointStorage() throws {
            let name = "sieg-checkpoint-" + UUID().uuidString, defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let plan = try ScreenGuidancePlan(title: "Long workflow", steps: (0..<15).map { .init(instruction: "Step \($0)", targetText: "Target \($0)", expectedText: "") }).validated()
            let journal = CompanionTaskJournal(defaults: defaults)
            let id = journal.begin(kind: .guidance, request: "Guide me", language: "en")
            journal.update(id, guidance: .init(plan: plan, index: 8))
            let restored = CompanionTaskJournal(defaults: defaults)
            #expect(restored.tasks.first?.state == .paused && restored.tasks.first?.guidance?.index == 8)
            #expect(!WalkthroughCheckpoint(plan: plan, index: 15).valid)
        }
        @Test("G03.05 · Pinning and archiving keep original conversation contents and persist")
        func historyOrganization() async throws {
            let a = LocalChatConversation(id: "a", persona: .sig, title: "Weather", updatedAt: Date(timeIntervalSince1970: 1), messages: [.init(role: .user, text: "Recife")])
            let b = LocalChatConversation(id: "b", persona: .ada, title: "Code", updatedAt: Date(timeIntervalSince1970: 2), messages: [])
            let store = MemoryLocalChatStore([a,b]), model = LocalChatViewModel(generator: UnavailableLocalChatEngine(), store: store)
            await model.prepare(); await model.setPinned("a", true)
            #expect(model.matchingConversations().map(\.id) == ["a", "b"])
            #expect(model.matchingConversations("recife").map(\.id) == ["a"])
            await model.setArchived("a", true)
            #expect(model.matchingConversations().map(\.id) == ["b"])
            let restored = LocalChatViewModel(generator: UnavailableLocalChatEngine(), store: store); await restored.prepare()
            #expect(restored.matchingConversations(archived: true).first?.messages == a.messages)
        }
        @Test("G30.04 · Document reading includes the last PDF page and rejects a symbolic-link attachment")
        func documentPages() throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("sieg-pdf-test-"+UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("example.pdf")
            var bounds = CGRect(x: 0, y: 0, width: 400, height: 500)
            let consumer = try #require(CGDataConsumer(url: url as CFURL))
            let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
            for text in ["First page: source alpha", "Final page: source omega"] {
                context.beginPDFPage(nil); context.textPosition = CGPoint(x: 30, y: 440)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 14, nil)]))
                CTLineDraw(line, context); context.endPDFPage()
            }
            context.closePDF()
            let document = try CompanionDocument.read(url)
            #expect(document.pages.count == 2 && !document.truncated)
            #expect(document.text.contains("source alpha") && document.text.contains("source omega"))
            let library = CompanionArtifactLibrary(directory: root.appendingPathComponent("library"))
            library.saveDocument(document)
            let stored = try #require(library.items.first), storedURL = try #require(library.url(for: stored))
            #expect(storedURL.pathExtension == "pdf")
            #expect(try Data(contentsOf: storedURL) == Data(contentsOf: url))
            let reopened = try CompanionDocument.read(storedURL)
            #expect(reopened.pages.count == 2 && reopened.text.contains("source omega"))
            let textURL = root.appendingPathComponent("example.txt"); try Data("Text fixture".utf8).write(to: textURL)
            let link = root.appendingPathComponent("link.txt"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: textURL)
            #expect(throws: (any Error).self) { try CompanionDocument.read(link) }
        }
        @Test("G30.05 · Workflow retry retains a completed step and does not execute it twice")
        func workflowRetry() async throws {
            let journal = CompanionTaskJournal(), runner = CompanionWorkflowRunner(journal: journal)
            defer { runner.shutdown() }
            var calls: [String] = [], fail = true
            runner.executor = { step, context, _ in
                calls.append(step.request)
                if step.request == "second", fail { fail = false; throw ResearchFailure.unavailable }
                if step.request == "second" { #expect(context.contains("first result")) }
                return step.request + " result"
            }
            let id = try runner.start(title: "Pipeline", steps: [.init(persona: .ada, request: "first"), .init(persona: .toni, request: "second")], language: "en")
            try await PresentationWait.until { journal.tasks.first?.state == .failed && runner.activeID == nil }
            let steps = try #require(journal.tasks.first?.workflow)
            #expect(steps[0].result == "first result" && steps[1].result == nil)
            try runner.start(title: "Pipeline", steps: steps, language: "en", resuming: id)
            try await PresentationWait.until { journal.tasks.first?.state == .completed && runner.activeID == nil }
            #expect(journal.tasks.count == 1 && calls == ["first", "second", "second"])
            #expect(journal.tasks.first?.fullResult.contains("second result") == true)
        }
        @Test("G30.05 · Daily routines require opt-in, coalesce missed runs and keep the next occurrence in the future")
        func routineSchedule() async throws {
            let routines = CompanionRoutines(), now = Date()
            defer { routines.stop() }
            let calendar = Calendar.current, components = calendar.dateComponents([.hour, .minute], from: now)
            let routine = CompanionRoutine(title: "Fixture", kind: .briefing, prompt: "Fixture agenda", hour: components.hour!, minute: components.minute!, timezone: calendar.timeZone.identifier, language: "pt-BR", nextRun: now.addingTimeInterval(-60))
            var calls = 0
            routines.execute = { _ in calls += 1 }
            routines.add(routine); routines.start(); routines.tick(now: now)
            #expect(!routines.items[0].enabled && calls == 0)
            routines.setEnabled(routine.id, true, now: now.addingTimeInterval(-90000))
            routines.tick(now: now); routines.tick(now: now)
            try await PresentationWait.until { routines.items[0].lastRun != nil && routines.activeID == nil }
            routines.tick(now: now)
            #expect(calls == 1 && routines.items[0].nextRun > now)
            #expect(routines.items[0].failures == 0)
        }
    }
}
