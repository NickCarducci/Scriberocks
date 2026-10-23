import UIKit

/// The system share sheet, presented from whatever is on top. Sharing text
/// with a link lets Messages show the link's preview (scribe.rocks/app).
enum ShareSheet {
    @MainActor
    static func present(_ items: [Any]) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.maxX - 40, y: top.view.bounds.maxY - 60, width: 1, height: 1)
        top.present(sheet, animated: true)
    }
}
