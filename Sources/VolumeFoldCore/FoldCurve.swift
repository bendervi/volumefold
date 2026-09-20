import Foundation

public enum FoldCurve {
    public static func multiplier(angle: Double, deadpoint: Double) -> Double {
        guard angle.isFinite, deadpoint.isFinite else { return 0 }
        return min(1, max(0, (angle - 5) / (min(120, max(10, deadpoint)) - 5)))
    }

    public static func normalVolume(audible: Double, multiplier: Double) -> Double? {
        guard audible.isFinite, multiplier.isFinite, multiplier > 0.01 else { return nil }
        return min(1, max(0, audible / multiplier))
    }
}
