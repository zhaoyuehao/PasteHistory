import Foundation

extension IvoryTreeEntry {
    init(item: ClipItem, index: Int) {
        let display = ClipPresentation(item: item)
        self.init(id: item.id,
                  title: display.imageFirst ? display.compactTitle : String((item.text ?? item.summary).prefix(500)),
                  index: index, source: item.sourceApp ?? "",
                  date: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                  pinned: item.pinned, thumbnail: item.thumbnailData, imageFirst: display.imageFirst)
    }
}
