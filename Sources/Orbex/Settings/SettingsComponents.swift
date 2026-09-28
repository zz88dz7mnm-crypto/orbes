import SwiftUI

// Piezas chicas que comparten las secciones de Configuración.

/// Texto de ayuda chico (debajo de un control o al pie de una sección).
struct SettingsFootnote: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Selector de hora en punto (00:00 – 23:00).
struct SettingsHourPicker: View {
    let title: String
    @Binding var hour: Int

    var body: some View {
        Picker(title, selection: $hour) {
            ForEach(0..<24, id: \.self) { h in
                Text(SettingsFormat.hour(h)).tag(h)
            }
        }
    }
}

/// Deslizador con su valor a la derecha (y botón opcional para volver al valor por defecto).
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 140)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }
}

enum SettingsFormat {
    static func hour(_ h: Int) -> String {
        String(format: "%02d:00", h)
    }

    static func percent(_ v: Double) -> String {
        "\(Int((v * 100).rounded())) %"
    }

    /// "+3 pt", "−2 pt", "0 pt".
    static func signedPoints(_ v: Double) -> String {
        let n = Int(v.rounded())
        if n == 0 { return "0 pt" }
        return n > 0 ? "+\(n) pt" : "−\(-n) pt"
    }

    static func seconds(_ v: Double) -> String {
        "\(Int(v.rounded())) s"
    }

    static func minutes(_ m: Int) -> String {
        m == 1 ? "1 minuto" : "\(m) minutos"
    }
}

extension Binding where Value == [String] {
    /// `Binding<Bool>` que es `true` cuando `item` NO está en la lista.
    /// Sirve para listas de "silenciados": prender el interruptor lo saca de la lista.
    func excluding(_ item: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { !self.wrappedValue.contains(item) },
            set: { isOn in
                var list = self.wrappedValue
                list.removeAll { $0 == item }
                if !isOn { list.append(item) }
                if list != self.wrappedValue { self.wrappedValue = list }
            })
    }
}
