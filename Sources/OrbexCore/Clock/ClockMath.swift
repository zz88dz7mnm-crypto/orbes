import Foundation

/// Rectángulo simple en `Double` (sin CoreGraphics, para poder probarlo en cualquier plataforma).
public struct ClockRect: Equatable, Codable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public func intersects(_ o: ClockRect) -> Bool { x < o.maxX && o.x < maxX && y < o.maxY && o.y < maxY }
}

/// Ángulos de las agujas en grados, en sentido horario desde las 12.
public struct HandAngles: Equatable, Sendable {
    public var hour: Double, minute: Double, second: Double
    public init(hour: Double, minute: Double, second: Double) { self.hour = hour; self.minute = minute; self.second = second }
}

public enum ClockMath {
    /// `smooth` = segundero de barrido continuo (tipo Rolex); si no, salta de a un segundo.
    public static func angles(hour: Int, minute: Int, second: Int, nanosecond: Int = 0, smooth: Bool = true) -> HandAngles {
        let frac = smooth ? Double(nanosecond) / 1_000_000_000 : 0
        let s = Double(second) + frac
        let m = Double(minute) + s / 60
        let h = Double(hour % 12) + m / 60
        return HandAngles(hour: h * 30, minute: m * 6, second: s * 6)
    }

    public static func angles(for date: Date, calendar: Calendar = .current, smooth: Bool = true) -> HandAngles {
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return angles(hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0,
                      nanosecond: c.nanosecond ?? 0, smooth: smooth)
    }

    public static func roman(_ n: Int) -> String {
        guard n > 0, n < 4000 else { return "" }
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var v = n, out = ""
        for (k, s) in table { while v >= k { out += s; v -= k } }
        return out
    }

    /// Números de la esfera en orden horario empezando por las 12.
    public static func numerals(roman useRoman: Bool) -> [String] {
        [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map { useRoman ? roman($0) : String($0) }
    }

    static let weekdaysES = ["DOM", "LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB"]

    /// Texto de la ventanita de fecha: "LUN 28".
    public static func dateWindowText(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.weekday, .day], from: date)
        let wd = weekdaysES[((c.weekday ?? 1) - 1 + 7) % 7]
        return "\(wd) \(c.day ?? 1)"
    }

    public static func dayText(_ date: Date, calendar: Calendar = .current) -> String {
        String(calendar.component(.day, from: date))
    }

    /// Punto sobre una órbita (y hacia abajo, 0° = las 12, sentido horario), relativo al centro.
    public static func orbitPoint(angle degrees: Double, radius: Double) -> (x: Double, y: Double) {
        let r = degrees * .pi / 180
        return (radius * sin(r), -radius * cos(r))
    }

    /// Mantiene el marco dentro del área visible.
    public static func clamp(frame f: ClockRect, to v: ClockRect) -> ClockRect {
        var r = f
        r.x = min(max(r.x, v.x), max(v.x, v.maxX - r.w))
        r.y = min(max(r.y, v.y), max(v.y, v.maxY - r.h))
        return r
    }

    /// Imanta el marco a los bordes del área visible si queda a menos de `threshold` puntos.
    public static func snap(frame: ClockRect, to v: ClockRect, threshold: Double) -> ClockRect {
        var r = clamp(frame: frame, to: v)
        if r.x - v.x <= threshold { r.x = v.x } else if v.maxX - r.maxX <= threshold { r.x = v.maxX - r.w }
        if r.y - v.y <= threshold { r.y = v.y } else if v.maxY - r.maxY <= threshold { r.y = v.maxY - r.h }
        return r
    }
}
