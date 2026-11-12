import AppKit
import SwiftUI
import VyronAutomation

struct VyronComputerPreviewView: View {
    @ObservedObject var model: AutomationModel

    var body: some View {
        VStack(alignment: .leading, spacing: VyronComputerPreviewStyle.spacing) {
            HStack(spacing: VyronComputerPreviewStyle.compactSpacing) {
                Image(systemName: VyronSymbols.computerPreview)
                Text(VyronControlText.livePreview)
                Spacer(minLength: 0)
                if let app = model.selectedApplication {
                    Text(app.name).foregroundStyle(Palette.muted).lineLimit(1)
                }
                if model.isFollowingTask || model.isPlanning || model.isExecuting {
                    Button(VyronAppText.automationStopTask, role: .destructive) {
                        model.stopVisibleComputerWork()
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(VyronComputerPreviewStyle.title)
            if !model.screenCaptureGranted {
                VStack(alignment: .leading, spacing: VyronComputerPreviewStyle.spacing) {
                    Text(VyronControlText.previewPermission)
                    Button(VyronControlText.allowPreview) { model.requestScreenCapture() }
                        .buttonStyle(AccentButtonStyle())
                }
                .font(VyronComputerPreviewStyle.caption)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let preview = model.controlPreview, let image = NSImage(data: preview.imageData) {
                previewImage(image, preview: preview)
            } else {
                Text(model.controlPreviewMessage ?? VyronControlText.previewWaiting)
                    .font(VyronComputerPreviewStyle.caption)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: VyronComputerPreviewStyle.height, alignment: .center)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let feedback = model.controlFeedback,
                    feedback.applicationID == model.selectedApplicationID,
                    context.date.timeIntervalSince(feedback.sentAt)
                        < VyronComputerPreviewStyle.actionVisibilitySeconds {
                    Label(feedback.title, systemImage: VyronSymbols.checkmark)
                        .foregroundStyle(Palette.success)
                } else {
                    Text(VyronControlText.previewLocal).foregroundStyle(Palette.muted)
                }
            }
            .font(VyronComputerPreviewStyle.caption)
        }
        .padding(VyronComputerPreviewStyle.padding)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: VyronComputerPreviewStyle.radius))
        .overlay {
            RoundedRectangle(cornerRadius: VyronComputerPreviewStyle.radius).stroke(Palette.border)
        }
    }

    private func previewImage(_ image: NSImage, preview: VyronMacControlPreview) -> some View {
        GeometryReader { geometry in
            let frame = fittedFrame(image.size, in: geometry.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityLabel(VyronControlText.livePreview)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let feedback = model.controlFeedback,
                        feedback.applicationID == preview.applicationID,
                        context.date.timeIntervalSince(feedback.sentAt)
                            < VyronComputerPreviewStyle.actionVisibilitySeconds,
                        let target = feedback.targetFrame,
                        let unitFrame = preview.unitRect(for: target) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: VyronComputerPreviewStyle.highlightRadius)
                                .strokeBorder(Palette.controlAccent, lineWidth: VyronComputerPreviewStyle.highlightWidth)
                                .frame(width: unitFrame.width * frame.width, height: unitFrame.height * frame.height)
                                .offset(
                                    x: frame.minX + unitFrame.minX * frame.width,
                                    y: frame.minY + unitFrame.minY * frame.height
                                )
                            VyronComputerPointer()
                                .position(VyronComputerPointerGeometry.previewPoint(for: unitFrame, in: frame))
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: VyronComputerPreviewStyle.height)
        .clipped()
    }

    private func fittedFrame(_ source: CGSize, in available: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0 else { return .zero }
        let scale = min(available.width / source.width, available.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: (available.width - size.width) / 2,
            y: (available.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
