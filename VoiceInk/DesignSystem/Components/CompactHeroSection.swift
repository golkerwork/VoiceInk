import SwiftUI

struct CompactHeroSection: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    var maxDescriptionWidth: CGFloat? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.Palette.accentText)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.Palette.accent.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.Palette.accent.opacity(0.30), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: maxDescriptionWidth, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
