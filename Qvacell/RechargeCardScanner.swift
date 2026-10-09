import SwiftUI
import VisionKit

struct RechargeCardScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onCodeScanned: (String) -> Void

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScannerRepresentable(onCodeScanned: { code in
                onCodeScanned(code)
                dismiss()
            })
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
            }
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.7), lineWidth: 2)
                    .frame(width: 280, height: 70)
            }
            .overlay(alignment: .bottom) {
                Text("Apunta la cámara al código de recarga")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.bottom, 48)
            }
        } else {
            ContentUnavailableView(
                "Escáner no disponible",
                systemImage: "camera.slash",
                description: Text("Este dispositivo no soporta escaneo de texto.")
            )
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        try? controller.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCodeScanned: (String) -> Void
        private var lastCandidate: String?
        private var confirmed = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            processItems(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            processItems(allItems)
        }

        private func processItems(_ items: [RecognizedItem]) {
            guard !confirmed else { return }
            for item in items {
                guard case .text(let text) = item else { continue }
                let digits = text.transcript.filter(\.isNumber)
                guard digits.count == 16 else { continue }
                if digits == lastCandidate {
                    confirmed = true
                    DispatchQueue.main.async {
                        self.onCodeScanned(digits)
                    }
                    return
                }
                lastCandidate = digits
            }
        }
    }
}
