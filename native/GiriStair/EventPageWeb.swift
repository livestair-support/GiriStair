import Foundation

// MARK: - 0.36 イベントページのURL読み取り（ツイプラなど）
//
// ページの文字（HTML）を行に分け、画面の読み取り（OCR）と同じ判断（giriEventPageDraft）に渡す。
// 特定のサイトの決まった位置は使わず、見出し・段落・リストの区切りと、Xのリンク（title の「@ID」・x.com のリンク）だけを使う。
// 会が終わるまで、会を開いた時にページを読み直して参加者の増減を出す（反映するかはユーザーが選ぶ）。

/// ページの文字の1行。見出し（h1〜h6）は level 1〜6、本文は 0。
struct GiriWebLine: Equatable {
    var text: String
    var level: Int = 0
    /// その行のXのID（リンクの title の「@ID」や x.com・twitter.com のリンクから。1つに決まる時だけ）。
    var handle: String = ""
    /// 同じ見出し・段落の中で <br> で折り返した続きの行。
    var continuesBlock: Bool = false
}

/// 読んだページ。title はページの名前（og:title か <title>）。
struct GiriWebDocument: Equatable {
    var title: String = ""
    var lines: [GiriWebLine] = []
    var text: String { lines.map(\.text).joined(separator: "\n") }
}

/// 0.36：ページで読んだ参加者・キャンセル待ちの1人（照合したあとの名前と、XのID）。
struct GiriPageEntry: Codable, Equatable {
    var name: String = ""
    /// @ を付けないXのID。分からない時は空。
    var handle: String = ""
}

extension GiriPageEntry {
    private enum CodingKeys: String, CodingKey { case name, handle }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        handle = try c.decodeIfPresent(String.self, forKey: .handle) ?? ""
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        if !handle.isEmpty { try c.encode(handle, forKey: .handle) }
    }
}

/// 0.36：ページを読んだ時点の参加者・キャンセル待ち（リザーバー）と、ページに書いてある参加者の人数。
struct GiriParticipantPage: Equatable {
    var participants: [GiriPageEntry] = []
    var reserves: [GiriPageEntry] = []
    var listedCount: Int? = nil
}

/// 0.36：ページの参加者を確かめる状態。知らない値（新しい版の値）は「やめた」として読む。
enum GiriParticipantSyncState: String, Equatable {
    /// 会が終わるまで、会を開いた時にページを読み直す。
    case watching
    /// 会が終わった。最後に読んだ内容で参加者を確定してもらう（もうページは読まない）。
    case confirming
    /// 参加者を確定した。
    case confirmed
    /// 確かめるのをやめた（自分が行かなかった会も、会が終わったらここ）。
    case stopped
}

/// 0.36：イベントページ（ツイプラなど）のURLと、最後に読んだ参加者・ユーザーが反映するかを決めた時の参加者。
/// 増減は「決めた時のページ」と「今のページ」で比べるので、手で足した人・外した人はそのまま残る。
struct GiriParticipantSync: Codable, Equatable {
    var url: String = ""
    var state: GiriParticipantSyncState = .watching
    /// 最後にページを読んだ時刻。
    var checkedAt: Date? = nil
    /// 最後に読んだページの参加者・キャンセル待ち。
    var pageParticipants: [GiriPageEntry] = []
    var pageReserves: [GiriPageEntry] = []
    /// ユーザーが増減を反映する・しないを決めた時のページの参加者・キャンセル待ち。
    var decidedParticipants: [GiriPageEntry] = []
    var decidedReserves: [GiriPageEntry] = []
    /// ページに書いてある参加者の人数（「参加者 (25人／定員25人)」）。
    var listedCount: Int? = nil

    /// 会を開いた時にページを読み直すか（会が終わるまで）。
    var isWatching: Bool { state == .watching }

    mutating func record(_ page: GiriParticipantPage, at date: Date) {
        pageParticipants = page.participants
        pageReserves = page.reserves
        listedCount = page.listedCount
        checkedAt = date
    }

    /// 今のページの増減を反映した・しなかった：次からは今のページと比べる（同じ増減を2回聞かない）。
    mutating func markDecided() {
        decidedParticipants = pageParticipants
        decidedReserves = pageReserves
    }
}

extension GiriParticipantSync {
    private enum CodingKeys: String, CodingKey {
        case url, state, checkedAt, pageParticipants, pageReserves, decidedParticipants, decidedReserves, listedCount
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        state = (try c.decodeIfPresent(String.self, forKey: .state)).flatMap(GiriParticipantSyncState.init(rawValue:)) ?? .stopped
        checkedAt = (try c.decodeIfPresent(String.self, forKey: .checkedAt)).flatMap { GiriDates.parse($0) }
        pageParticipants = try c.decodeIfPresent([GiriPageEntry].self, forKey: .pageParticipants) ?? []
        pageReserves = try c.decodeIfPresent([GiriPageEntry].self, forKey: .pageReserves) ?? []
        decidedParticipants = try c.decodeIfPresent([GiriPageEntry].self, forKey: .decidedParticipants) ?? []
        decidedReserves = try c.decodeIfPresent([GiriPageEntry].self, forKey: .decidedReserves) ?? []
        listedCount = try c.decodeIfPresent(Int.self, forKey: .listedCount)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url, forKey: .url)
        try c.encode(state.rawValue, forKey: .state)
        if let checkedAt { try c.encode(GiriDates.timestamp(checkedAt), forKey: .checkedAt) }
        if !pageParticipants.isEmpty { try c.encode(pageParticipants, forKey: .pageParticipants) }
        if !pageReserves.isEmpty { try c.encode(pageReserves, forKey: .pageReserves) }
        if !decidedParticipants.isEmpty { try c.encode(decidedParticipants, forKey: .decidedParticipants) }
        if !decidedReserves.isEmpty { try c.encode(decidedReserves, forKey: .decidedReserves) }
        if let listedCount { try c.encode(listedCount, forKey: .listedCount) }
    }
}

// MARK: - URL

/// 貼り付けた文（「タイトル https://twipla.jp/events/…」など）から、ページのURLを取り出す。
/// 「twipla.jp/events/…」のように https:// がない時は付ける。http(s) 以外は使わない。
func giriEventPageURL(from raw: String) -> URL? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    var candidate: String
    if let range = text.range(of: #"(?i)https?://[^\s　<>"'「」『』（）()]+"#, options: .regularExpression) {
        candidate = String(text[range])
    } else if text.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(/\S*)?$"#, options: .regularExpression) != nil {
        candidate = "https://" + text
    } else {
        return nil
    }
    // 文の終わりの句読点はURLに入れない。
    candidate = candidate.replacingOccurrences(of: #"[。、．，.,!！?？]+$"#, with: "", options: .regularExpression)
    guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = url.host, !host.isEmpty else { return nil }
    return url
}

// MARK: - HTML → 行

/// 受け取ったページのバイト列を文字にする（HTTP の charset → <meta charset> → UTF-8・Shift_JIS・EUC-JP の順）。
func giriDecodeHTMLData(_ data: Data, textEncodingName: String? = nil) -> String {
    var encodings: [String.Encoding] = []
    func add(_ name: String?) {
        guard let name = name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        switch name {
        case "utf-8", "utf8": encodings.append(.utf8)
        case "shift_jis", "shift-jis", "sjis", "windows-31j", "cp932", "x-sjis": encodings.append(.shiftJIS)
        case "euc-jp", "x-euc-jp": encodings.append(.japaneseEUC)
        case "iso-2022-jp": encodings.append(.iso2022JP)
        default: break
        }
    }
    add(textEncodingName)
    let head = String(decoding: data.prefix(4096), as: UTF8.self)
    if let groups = giriRegexGroups(#"(?i)charset\s*=\s*["']?([A-Za-z0-9_\-]+)"#, in: head).first { add(groups[1]) }
    encodings.append(contentsOf: [.utf8, .shiftJIS, .japaneseEUC])
    for encoding in encodings {
        if let text = String(data: data, encoding: encoding) { return text }
    }
    return String(decoding: data, as: UTF8.self)
}

/// HTML の文字参照（&amp; &nbsp; &#12354; &#x3042; など）を文字にする。知らない名前はそのまま残す。
func giriDecodeHTMLEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ",
        "hellip": "…", "mdash": "—", "ndash": "–", "middot": "·", "bull": "•", "copy": "©", "reg": "®", "trade": "™",
        "laquo": "«", "raquo": "»", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "times": "×", "divide": "÷",
        "yen": "¥", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "hearts": "♥", "star": "☆", "minus": "−"
    ]
    guard let regex = try? NSRegularExpression(pattern: #"&(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});"#) else { return text }
    let source = text as NSString
    var output = ""
    var cursor = 0
    for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
        output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let body = source.substring(with: match.range(at: 1))
        var replacement: String?
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            if let value = UInt32(body.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(value) { replacement = String(Character(scalar)) }
        } else if body.hasPrefix("#") {
            if let value = UInt32(body.dropFirst()), let scalar = Unicode.Scalar(value) { replacement = String(Character(scalar)) }
        } else {
            replacement = named[body.lowercased()]
        }
        output += replacement ?? source.substring(with: match.range)
        cursor = match.range.location + match.range.length
    }
    output += source.substring(from: cursor)
    return output
}

/// タグの属性（名前は小文字）。
func giriHTMLAttributes(_ raw: String) -> [String: String] {
    var attributes: [String: String] = [:]
    for groups in giriRegexGroups(#"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#, in: raw) {
        let name = groups[1].lowercased()
        guard attributes[name] == nil else { continue }
        let value = !groups[2].isEmpty ? groups[2] : (!groups[3].isEmpty ? groups[3] : groups[4])
        attributes[name] = giriDecodeHTMLEntities(value)
    }
    return attributes
}

/// リンクのXのID：title が「@ID」、または x.com・twitter.com の人のページへのリンク。分からない時は空。
func giriWebXHandle(href: String, title: String) -> String {
    if let groups = giriRegexGroups(#"^\s*[@＠]([A-Za-z0-9_]{1,15})\s*$"#, in: title).first { return groups[1] }
    let reserved: Set<String> = ["intent", "share", "home", "hashtag", "search", "i", "settings", "explore", "login", "logout",
                                 "signup", "messages", "notifications", "compose", "privacy", "tos", "about", "account"]
    if let groups = giriRegexGroups(#"(?i)^(?:https?:)?//(?:www\.|mobile\.)?(?:x|twitter)\.com/(?:#!/)?([A-Za-z0-9_]{1,15})(?:[/?#]|$)"#,
                                    in: href.trimmingCharacters(in: .whitespacesAndNewlines)).first,
       !reserved.contains(groups[1].lowercased()) {
        return groups[1]
    }
    return ""
}

/// HTML を、見出し・段落・リストなどの区切りごとの行にする。script・style・head などの中は読まない。
func giriWebDocument(html raw: String) -> GiriWebDocument {
    var document = GiriWebDocument()
    var html = raw.replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"<[!?][^>]*>"#, with: " ", options: .regularExpression)
    // ページの名前：og:title → <title>。
    var ogTitle = ""
    for groups in giriRegexGroups(#"(?i)<meta\b([^>]*)>"#, in: html) {
        let attributes = giriHTMLAttributes(groups[1])
        if (attributes["property"] ?? attributes["name"])?.lowercased() == "og:title", let content = attributes["content"] {
            ogTitle = content.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
    }
    let plainTitle = giriRegexGroups(#"(?is)<title\b[^>]*>(.*?)</title\s*>"#, in: html).first.map { giriDecodeHTMLEntities($0[1]) } ?? ""
    document.title = giriCollapsedWebText(ogTitle.isEmpty ? plainTitle : ogTitle)
    html = html.replacingOccurrences(of: #"(?is)<(script|style|noscript|template|svg|iframe|select|head|object)\b[^>]*>.*?</\1\s*>"#,
                                      with: " ", options: .regularExpression)
    if let body = html.range(of: #"(?i)<body\b"#, options: .regularExpression) { html = String(html[body.lowerBound...]) }

    let blockTags: Set<String> = ["address", "article", "aside", "blockquote", "caption", "center", "dd", "details", "dialog", "div",
                                  "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "header", "hr", "li", "main",
                                  "nav", "ol", "p", "pre", "section", "summary", "table", "tbody", "thead", "tfoot", "tr", "td",
                                  "th", "ul", "legend"]
    var current = ""
    var handles: [String] = []
    var heading = 0
    var anchorHandle: String?
    var nextContinues = false

    func flush(byLineBreak: Bool) {
        let text = giriCollapsedWebText(current)
        if !text.isEmpty {
            let unique = Set(handles.map { $0.lowercased() })
            document.lines.append(GiriWebLine(text: text, level: heading, handle: unique.count == 1 ? (handles.first ?? "") : "",
                                              continuesBlock: nextContinues))
        }
        nextContinues = byLineBreak && !text.isEmpty
        current = ""
        handles = []
    }

    guard let tagRegex = try? NSRegularExpression(pattern: #"<(/?)([A-Za-z][A-Za-z0-9]*)\b([^>]*)>"#) else { return document }
    let source = html as NSString
    var cursor = 0
    func appendText(_ raw: String) {
        let text = giriDecodeHTMLEntities(raw)
        guard !text.isEmpty else { return }
        current += text
        if let anchorHandle, !anchorHandle.isEmpty, text.contains(where: { !$0.isWhitespace }) { handles.append(anchorHandle) }
    }
    for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
        if match.range.location > cursor { appendText(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))) }
        cursor = match.range.location + match.range.length
        let closing = !source.substring(with: match.range(at: 1)).isEmpty
        let name = source.substring(with: match.range(at: 2)).lowercased()
        let attributes = source.substring(with: match.range(at: 3))
        if name == "br" {
            flush(byLineBreak: true)
        } else if let level = name.count == 2 && name.hasPrefix("h") ? Int(String(name.dropFirst())) : nil, (1...6).contains(level) {
            flush(byLineBreak: false)
            heading = closing ? 0 : level
        } else if blockTags.contains(name) {
            flush(byLineBreak: false)
        } else if name == "a" {
            if closing {
                anchorHandle = nil
                // 並んだリンク（タグ・ボタン）の文字がつながらないようにする。
                current += " "
            } else {
                let values = giriHTMLAttributes(attributes)
                anchorHandle = giriWebXHandle(href: values["href"] ?? "", title: values["title"] ?? "")
            }
        }
    }
    if cursor < source.length { appendText(source.substring(from: cursor)) }
    flush(byLineBreak: false)
    return document
}

/// 空白（改行・タブ・ノーブレークスペースを含む）を1つにして、前後の空白（全角も）を外す。
func giriCollapsedWebText(_ raw: String) -> String {
    raw.replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: #"[ \t\r\n\f\x{200B}]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}")))
}

/// 文字が少なく参加者の見出しもないページ（開いてから中身を出すページ）は、端末で表示してから読み直す。
func giriWebDocumentNeedsRendering(_ document: GiriWebDocument) -> Bool {
    if document.lines.contains(where: { giriParticipantHeader($0.text) != nil }) { return false }
    return document.lines.reduce(0) { $0 + $1.text.count } < 400
}

/// 画面の読み取りと同じ判断に渡すための、行の位置と大きさ。見出しは大きい文字、本文は同じ大きさにする。
/// 折り返した続きの行（<br>）は詰めて、別の段落は間を空ける（段落をまたいでタイトルの続きにしない）。
func giriOCRLines(_ document: GiriWebDocument) -> [GiriOCRLine] {
    func height(_ level: Int) -> Double {
        switch level {
        case 1: return 0.030
        case 2: return 0.026
        case 3: return 0.022
        case 4, 5, 6: return 0.018
        default: return 0.015
        }
    }
    var output: [GiriOCRLine] = []
    var y = 0.0
    var previous = 0.0
    for line in document.lines {
        let size = height(line.level)
        if !output.isEmpty { y += max(previous, size) * (line.continuesBlock ? 1.25 : 3.0) }
        output.append(GiriOCRLine(text: line.text, midX: 0.5, midY: y, height: size, minX: 0.05))
        previous = size
    }
    return output
}

/// ページの名前のうち、ページの本文にもある書き方（「会の名前 - TwiPla」の「 - TwiPla」を外した名前など）。
func giriWebEventTitle(_ document: GiriWebDocument) -> String? {
    let full = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !full.isEmpty else { return nil }
    var candidates: [String] = []
    for pattern in [#"\s+[-–—|｜]\s+[^-–—|｜]+$"#, #"^[^-–—|｜]+\s+[-–—|｜]\s+"#] {
        let stripped = full.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped != full && stripped.count >= 2 { candidates.append(stripped) }
    }
    candidates.append(full)
    let keys = document.lines.map { playerSearchKey($0.text) }
    return candidates.first { candidate in
        let key = playerSearchKey(candidate)
        return !key.isEmpty && keys.contains { $0 == key || ($0.contains(key) && key.count >= 4) }
    }
}

/// 行の文字 → XのID（同じ文字の行が別のIDの時は使わない）。
func giriWebHandles(_ document: GiriWebDocument) -> [String: String] {
    var handles: [String: String] = [:]
    var conflicts = Set<String>()
    for line in document.lines where !line.handle.isEmpty {
        let key = playerSearchKey(line.text)
        guard !key.isEmpty else { continue }
        if let existing = handles[key], existing.lowercased() != line.handle.lowercased() { conflicts.insert(key) }
        else { handles[key] = line.handle }
    }
    for key in conflicts { handles[key] = nil }
    return handles
}

/// ページから会の名前・日時・会場・主催・参加費・参加者・チーム・ルールを読む（画面の読み取りと同じ判断）。
/// 会の名前はページの名前（og:title・<title>）が本文にもある時はそれにし、参加者にはリンクのXのIDを付ける。
func giriEventPageDraft(web document: GiriWebDocument, url: String, known: [String], venues: [String], organizers: [String] = [],
                        venueRooms: [String: [String]] = [:], venueAddresses: [String: String] = [:],
                        now: Date = Date(), calendar: Calendar = .current) -> GiriEventPageDraft {
    var draft = giriEventPageDraft(lines: giriOCRLines(document), known: known, venues: venues, organizers: organizers,
                                   venueRooms: venueRooms, venueAddresses: venueAddresses, now: now, calendar: calendar)
    if let title = giriWebEventTitle(document) {
        var value = giriTrimmedEventPageTitle(title)
        if !draft.venue.isEmpty, value.hasPrefix(draft.venue) {
            let rest = String(value.dropFirst(draft.venue.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "　")))
            if rest.count >= 2 { value = rest }
        }
        draft.title = value
    }
    let handles = giriWebHandles(document)
    for index in draft.participants.indices {
        if let handle = handles[playerSearchKey(draft.participants[index].source)] { draft.participants[index].handle = handle }
    }
    draft.sourceURL = url
    return draft
}

/// 0.36：リンクのXのIDが登録したプレイヤーのXアカウントなら、その人にする（表示名が変わっても同じ人）。
/// owners はXのID（と @ID）の照合キー → プレイヤーの名前（GiriStore.xAccountOwners）。
func giriResolvingHandles(_ candidates: [GiriParticipantCandidate], owners: [String: String]) -> [GiriParticipantCandidate] {
    candidates.map { candidate in
        var value = candidate
        guard !value.handle.isEmpty, let owner = owners[playerSearchKey(value.handle)] ?? owners[playerSearchKey("@" + value.handle)] else { return value }
        value.name = owner
        value.registered = owner
        value.truncated = false
        return value
    }
}

/// 読み取りの確認の候補から、ページの参加者・キャンセル待ちを取り出す（確認画面で直した名前を使う。足した行は入れない）。
/// includesReserves：キャンセル待ち・補欠をリザーバーとして使う会（生大喜利）か。
func giriParticipantPage(_ draft: GiriEventPageDraft, includesReserves: Bool) -> GiriParticipantPage {
    func entries(_ section: GiriParticipantSection) -> [GiriPageEntry] {
        var seen = Set<String>()
        return draft.participants.compactMap { candidate in
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate.section == section, !candidate.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !name.isEmpty,
                  seen.insert(playerSearchKey(name)).inserted else { return nil }
            return GiriPageEntry(name: name, handle: candidate.handle)
        }
    }
    return GiriParticipantPage(participants: entries(.participants), reserves: includesReserves ? entries(.reserve) : [],
                               listedCount: draft.listedParticipantCount)
}

/// 0.36：スプシ系などリザーバーを入れない会では、キャンセル待ち・補欠を「不参加・キャンセル待ちなど」に入れて選ばない。
func giriDemotingReserves(_ candidates: [GiriParticipantCandidate]) -> [GiriParticipantCandidate] {
    candidates.map { candidate in
        guard candidate.section == .reserve else { return candidate }
        var value = candidate
        value.section = .other
        value.included = false
        return value
    }
}

// MARK: - 参加者の増減

/// 0.36：ページの参加者の増減（今の参加者・リザーバーに入っていない人だけ足す候補にし、入っている人だけ外す候補にする）。
struct GiriRosterChanges: Equatable {
    var joined: [GiriPageEntry] = []
    var left: [String] = []
    var reservesJoined: [GiriPageEntry] = []
    var reservesLeft: [String] = []

    var isEmpty: Bool { joined.isEmpty && left.isEmpty && reservesJoined.isEmpty && reservesLeft.isEmpty }
    var count: Int { joined.count + left.count + reservesJoined.count + reservesLeft.count }
}

/// 同じ人か：どちらもXのIDが分かる時はIDで、それ以外は名前で比べる。
func giriSamePageEntry(_ first: GiriPageEntry, _ second: GiriPageEntry) -> Bool {
    if !first.handle.isEmpty && !second.handle.isEmpty { return first.handle.lowercased() == second.handle.lowercased() }
    return playerSearchKey(first.name) == playerSearchKey(second.name)
}

/// 反映するかを決めた時のページと今のページを比べた増減。
func giriRosterChanges(_ sync: GiriParticipantSync, participants: [String], reserves: [String]) -> GiriRosterChanges {
    let current = Set(participants.map(playerSearchKey).filter { !$0.isEmpty })
    let currentReserves = Set(reserves.map(playerSearchKey).filter { !$0.isEmpty })
    func contains(_ list: [GiriPageEntry], _ entry: GiriPageEntry) -> Bool { list.contains { giriSamePageEntry($0, entry) } }
    var changes = GiriRosterChanges()
    changes.joined = sync.pageParticipants.filter { !contains(sync.decidedParticipants, $0) && !current.contains(playerSearchKey($0.name)) }
    changes.left = sync.decidedParticipants.filter { !contains(sync.pageParticipants, $0) && current.contains(playerSearchKey($0.name)) }.map(\.name)
    let joinedKeys = Set(changes.joined.map { playerSearchKey($0.name) })
    changes.reservesJoined = sync.pageReserves.filter { entry in
        let key = playerSearchKey(entry.name)
        return !contains(sync.decidedReserves, entry) && !currentReserves.contains(key) && !current.contains(key) && !joinedKeys.contains(key)
    }
    changes.reservesLeft = sync.decidedReserves.filter { !contains(sync.pageReserves, $0) && currentReserves.contains(playerSearchKey($0.name)) }.map(\.name)
    return changes
}

/// 選んだ増減を参加者・リザーバーに入れる（自分の立場は登録画面の保存と同じく欄から決め直す）。
/// リザーバーから参加者になった人は、リザーバーから外す。リザーバーは生大喜利だけ。
func giriApplyingRosterChanges(_ event: GiriEvent, _ changes: GiriRosterChanges, isSelf: (String) -> Bool) -> GiriEvent {
    var value = event
    let leftKeys = Set(changes.left.map(playerSearchKey))
    value.participants.removeAll { leftKeys.contains(playerSearchKey($0)) || $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    for entry in changes.joined where !value.participants.contains(where: { playerSearchKey($0) == playerSearchKey(entry.name) }) {
        value.participants.append(entry.name)
    }
    if value.eventFormat == .live {
        let joinedKeys = Set(changes.joined.map { playerSearchKey($0.name) })
        let reserveLeftKeys = Set(changes.reservesLeft.map(playerSearchKey))
        value.reserves.removeAll { name in
            let key = playerSearchKey(name)
            return key.isEmpty || reserveLeftKeys.contains(key) || joinedKeys.contains(key)
        }
        for entry in changes.reservesJoined {
            let key = playerSearchKey(entry.name)
            guard !value.reserves.contains(where: { playerSearchKey($0) == key }),
                  !value.participants.contains(where: { playerSearchKey($0) == key }) else { continue }
            value.reserves.append(entry.name)
        }
        if !changes.reservesJoined.isEmpty { value.hasReserves = true }
    }
    value.applyRosterSelfRole(isSelf: isSelf)
    return value
}

extension GiriEvent {
    /// 0.28：名簿を入れた生大喜利は、自分がいる欄（参加者・主催・リザーバー）から立場を決める。
    /// どの欄にもいない参加予定は観覧にする（登録画面の保存と、0.36 のページの増減の反映で同じ）。
    mutating func applyRosterSelfRole(isSelf: (String) -> Bool) {
        if eventFormat == .live && hasEnteredRoster && isParticipating && !isInterested && status != .canceled && listedSelfRole(isSelf: isSelf) == nil {
            selfRole = .spectator
        } else if selfRole == .spectator, listedSelfRole(isSelf: isSelf) != nil {
            selfRole = .player
        }
        selfRole = derivedSelfRole(isSelf: isSelf)
    }

    /// 0.36：ページの参加者を確かめる会で、会が終わったあとに参加者を確定してもらうか（自分が行った会だけ）。
    var asksParticipantConfirmation: Bool { isActualParticipant }
}
