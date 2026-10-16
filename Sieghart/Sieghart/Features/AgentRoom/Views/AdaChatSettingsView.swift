import SwiftUI

struct AdaChatSettingsView: View {
    @ObservedObject var chat: LocalChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.islandPreview) private var preview
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CompanionCharacter(size: 42, avatar: .ada, animates: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ada settings").font(.headline)
                    Text("Your senior coding companion.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            if preview {
                settingsContents
            } else {
                ScrollView { settingsContents }
            }
        }.padding(22).frame(width: 480).frame(height: preview ? nil : 580)
            .foregroundStyle(CompanionStyle.ink).background(CompanionStyle.background)
            .task { if !preview { await chat.github.restore() } }
    }

    private var settingsContents: some View {
        VStack(alignment: .leading, spacing: 14) {
                    if preview {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(AppleChatMode.allCases, id: \.self) { mode in
                                Label(mode.title, systemImage: chat.configuration.mode == mode ? "largecircle.fill.circle" : "circle")
                            }
                        }.font(.callout)
                    } else {
                        Picker("Apple model", selection: Binding(get: { chat.configuration.mode }, set: { chat.configure(mode: $0) })) {
                            ForEach(AppleChatMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                        }.pickerStyle(.radioGroup).disabled(chat.generatingID != nil)
                    }
                    Text(chat.configuration.mode.explanation).font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                    if chat.configuration.mode == .privateCloudThinking {
                        if preview { Text("Thinking · " + chat.configuration.reasoning.title).font(.callout).padding(8).frame(maxWidth: .infinity).background(CompanionStyle.separator, in: RoundedRectangle(cornerRadius: 8)) }
                        else {
                            Picker("Thinking", selection: Binding(get: { chat.configuration.reasoning }, set: { chat.configure(reasoning: $0) })) {
                                ForEach(AppleChatReasoning.allCases, id: \.self) { value in Text(value.title).tag(value) }
                            }.pickerStyle(.segmented).disabled(chat.generatingID != nil)
                        }
                        Text("Deep reasoning is enabled by default. More reasoning can take longer. The chat shows the answer and useful rationale, without a private reasoning transcript.")
                            .font(.caption).foregroundStyle(CompanionStyle.muted)
                    }
                    if let reason = chat.readiness.reason {
                        Text(reason).font(.caption).foregroundStyle(CompanionStyle.muted).textSelection(.enabled)
                    }
                    HStack {
                        Button("Check model again") { Task { await chat.prepare() } }
                        if chat.configuration.mode == .privateCloudThinking {
                            if preview { Text("Apple Cloud access").foregroundStyle(CompanionStyle.accent) }
                            else { Link("Apple Cloud access", destination: URL(string: "https://developer.apple.com/private-cloud-compute/")!) }
                        }
                    }.font(.caption)
                    Divider()
                    AdaGitHubConnectionView(model: chat.github)
                    Divider()
                    Text("Ada helps with code, architecture, debugging, reviews and developer workflow. Connected GitHub facts come from real account tools. Terminal execution, repository edits, live news and spending queries are not connected as chat tools yet.")
                        .font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
