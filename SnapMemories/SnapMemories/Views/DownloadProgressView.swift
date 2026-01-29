import SwiftUI

struct DownloadProgressView: View {
    let progress: Double
    let currentItem: String
    let successCount: Int
    let failedCount: Int
    let skippedCount: Int
    let totalCount: Int
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated download icon
            ZStack {
                Circle()
                    .stroke(.yellow.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)
                
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.yellow)
            }
            
            // Progress text
            VStack(spacing: 8) {
                Text("Downloading Memories...")
                    .font(.title2.weight(.semibold))
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
                
                Text(currentItem)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            // Stats
            HStack(spacing: 24) {
                StatBadge(value: successCount, label: "Saved", color: .green)
                StatBadge(value: skippedCount, label: "Skipped", color: .orange)
                StatBadge(value: failedCount, label: "Failed", color: .red)
            }
            
            // Progress bar
            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.yellow)
                
                HStack {
                    Text("\(successCount + skippedCount + failedCount)")
                    Spacer()
                    Text("\(totalCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            
            Text("Please keep the app open")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 70)
    }
}

#Preview {
    DownloadProgressView(
        progress: 0.45,
        currentItem: "Jan 15, 2024 3:45 PM",
        successCount: 23,
        failedCount: 2,
        skippedCount: 5,
        totalCount: 100
    )
}
