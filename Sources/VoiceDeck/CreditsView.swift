import SwiftUI
import TranscribeCore

private enum ProjectLinks {
    static let author = URL(string: "https://github.com/tommasinigiovanni")!
    static let repository = ReleaseChecker.repositoryURL
    static let issues = repository.appendingPathComponent("issues")
    static let license = repository.appendingPathComponent("blob/main/LICENSE")
}

struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Le persone e il progetto.").font(.system(size: 29, weight: .semibold)).tracking(-1)
                    Text("Autore, codice sorgente e riferimenti.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 15) {
                            Image(systemName: "waveform").font(.system(size: 38)).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("VoiceDeck").font(.system(size: 25, weight: .semibold)).tracking(-0.7)
                                Text("Audio, speaker e testo modificabile. Sul Mac o con OpenRouter.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        Text("Sviluppato da Giovanni Tommasini").font(.system(size: 16, weight: .semibold))
                        creditLink("Giovanni Tommasini su GitHub", detail: "github.com/tommasinigiovanni", symbol: "person.crop.circle", url: ProjectLinks.author)
                        creditLink("Repository del progetto", detail: "Codice sorgente e aggiornamenti", symbol: "chevron.left.forwardslash.chevron.right", url: ProjectLinks.repository)
                        creditLink("Segnalazioni e proposte", detail: "Issue su GitHub", symbol: "bubble.left.and.bubble.right", url: ProjectLinks.issues)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).voiceDeckCard()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Licenza e riferimenti").font(.system(size: 15, weight: .semibold))
                        Link("Licenza MIT", destination: ProjectLinks.license).font(.system(size: 12))
                        Text("VoiceDeck usa FluidAudio per la trascrizione locale e l’analisi degli speaker. In modalità OpenRouter, Nemotron 3.5 Transcribe viene utilizzato come servizio remoto. I pesi dei modelli locali vengono scaricati separatamente e non sono inclusi nell’app.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 18) { references }
                            VStack(alignment: .leading, spacing: 10) { references }
                        }.font(.system(size: 11))
                        Text("VoiceDeck non è un prodotto ufficiale NVIDIA o OpenRouter.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).voiceDeckCard()
                }
            }.padding(28).frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
    }

    @ViewBuilder private var references: some View {
        Link("FluidAudio · Apache 2.0", destination: URL(string: "https://github.com/FluidInference/FluidAudio")!)
        Link("Parakeet v3 · CC BY 4.0", destination: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!)
        Link("Speaker · OpenMDW 1.1", destination: URL(string: "https://huggingface.co/FluidInference/nemotron-3-diarization-coreml")!)
    }

    private func creditLink(_ title: String, detail: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).frame(width: 30).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(12).background(Palette.subtle.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
