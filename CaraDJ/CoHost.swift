import Foundation
import AVFoundation

// MARK: - Alex, Cara's co-host
// An original character: a West Coast hip-hop DJ who came up on a rival Los Santos station and now shares the mic
// with Cara. Not based on any real DJ or presenter.

enum CoHost {
    static let name = "Alex"
    static let fullName = "Alex"
    /// His voice when you haven't picked one (one of ElevenLabs' own voices: deep, warm, radio).
    static let defaultVoice = "nPczCjzI2devNBz1zQrb"

    static func voice(_ cfg: Config) -> String {
        let v = cfg.coVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultVoice : v
    }

    static let persona = """
    Alex is Cara's co-host: a laid-back West Coast hip-hop DJ with a big warm laugh, slow-burn comebacks and total confidence in his own taste. \
    He's an old-school crate-digger who talks breakbeats, vinyl, lowriders, taco trucks and car shows, thinks he can sing (he can't), \
    and is ruthlessly competitive at dominoes. He calls Cara "London" and teases her about pop music and tea; she calls him "Grandpa Vinyl" \
    and teases him about living in the past. Old rivals turned best mates: the bickering is affectionate and they always have each other's back. \
    He's smooth and unbothered where she's bubbly and chaotic. Clean language, no swearing.
    """

    /// Who's who on air: two Los Santos DJs in the studio, and the listener, who is someone else entirely.
    static let whoIsWho = """
    WHO'S WHO (never mix them up)
    - Cara and Alex are the two DJs, in the studio together. Both came up on Los Santos radio, on rival stations (Cara on Non Stop Pop FM, Alex on The Heat 104.9), and now they're co-hosts and old friends. With each other they talk like fellow DJs: studio banter, shared radio history, old rival-station trash talk.
    - The listener is someone else: a person at home or in the car, never in the studio, never speaking, and never Cara or Alex. Alex is NOT the listener.
    - Everything about the listener stays the listener's: the music is their pick (the station is named after what they put on), and their taste, listening habits, town and plans are theirs. Never pin any of it on Alex, and never talk to Alex as if he's the one listening.
    - When a DJ talks to the listener, make it obvious ("you at home", "you in the car", "whoever's listening"); when they talk to each other, they use names or nicknames.
    """

    static let bible = "Alex's backstory (fixed, never contradict it or add big new facts): he grew up in Los Santos, spun records at block parties in Davis as a teenager, and hosted the late-night show on The Heat 104.9, the hip-hop station that was forever beating Cara's old station in the ratings (or so he claims). These days he shares the mic with Cara far from the coast, and he only talks about Los Santos as his past."

    /// His Los Santos stories (used up before any repeats).
    static let lore: [String] = [
        "The night the power cut out at The Heat 104.9 and he kept the show going for forty minutes by beatboxing into a backup mic.",
        "The time he entered a lowrider show in Vespucci and his car hopped so high it set off every car alarm on the boulevard.",
        "The time he lost a dominoes tournament in Davis to a grandmother who never once looked up from her lemonade.",
        "The time he found a 'rare record' at a Mirror Park garage sale that turned out to be someone's homemade karaoke tape.",
        "The time he sang the station ID live and the request line lit up with people begging him to stop.",
        "The time he judged a taco truck contest and gave every single truck first place because he couldn't choose.",
        "The time he got lost in the Vinewood Hills looking for a house party and ended up DJing a very confused book club.",
        "The time he set up turntables on Vespucci Beach and the tide took one of his speakers.",
        "The time he dozed off during his own late-night show and listeners heard twelve minutes of snoring over an instrumental.",
        "The time he tried to teach a parrot on the Del Perro Pier to say the station's name and it only learned his laugh.",
        "The time his sneakers were so fresh he refused to walk on grass at an outdoor festival and had to be carried across the field.",
        "The time he challenged a mime on Vespucci Beach to a dance-off and lost, in total silence.",
        "The time he scratched a record so hard at a Davis block party that the needle flew into a bowl of salsa.",
        "The time he played the same song four times in a row by accident and announced it as a theme night.",
        "The time he took his lowrider through a car wash with the hydraulics still on.",
        "The time he got stuck in a Rockford Hills elevator with a big-shot record producer and pitched him a mixtape for nine floors.",
        "The time he ran a contest where the prize was lunch with him, nobody entered, and he ate both lunches.",
        "The time he grilled on the station roof and set off the sprinklers in the studio below.",
        "The time he wore a full matching tracksuit to a Vinewood premiere and the photographers thought he was the star.",
        "The time someone asked for his autograph at a gas station in Sandy Shores, then asked who he was.",
        "The time he tried to hike Mount Chiliad carrying a boombox and made it as far as the first bench.",
        "The time he spent a whole show arguing with a caller about the best breakfast burrito in Los Santos, and they were both right.",
        "The time he read out a shout-out list so long it lasted forty-five minutes and zero songs.",
        "The time his car stereo was so loud it rattled the windows of the station across the street, which happened to be Cara's.",
    ]
}

/// One turn in a Cara-and-Alex exchange.
struct DuoLine {
    /// "CARA" or "ALEX".
    let who: String
    let text: String
    var isCoHost: Bool { who == "ALEX" }
    var display: String { (isCoHost ? CoHost.name : "Cara") + ": " + text }
}

/// Puts the two voices together into one clip: each line trimmed and levelled, tight gaps, Cara a touch left, Alex a touch right.
enum DuoMixer {
    struct Clip: Sendable {
        let file: URL
        let coHost: Bool
    }

    static func render(_ clips: [Clip], to out: URL) throws {
        let rate = StingerMixer.rate
        var placed: [(start: Int, samples: [Float], coHost: Bool)] = []
        var pos = Int(0.1 * rate)
        for c in clips {
            var v = try StingerMixer.trim(StingerMixer.mono(StingerMixer.read(c.file)))
            if v.isEmpty { continue }
            // both voices sit at the same loudness
            let g = powf(10, (-19 - StingerMixer.activeDB(v)) / 20)
            for k in v.indices { v[k] *= g }
            placed.append((pos, v, c.coHost))
            pos += v.count + Int(Double.random(in: 0.12...0.26) * rate)
        }
        guard !placed.isEmpty else { throw StingerMixer.failure("there were no voices to mix") }
        let total = (placed.map { $0.start + $0.samples.count }.max() ?? 0) + Int(0.2 * rate)
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        for p in placed {
            let (gl, gr): (Float, Float) = p.coHost ? (0.86, 1.0) : (1.0, 0.86)
            for k in 0..<p.samples.count where p.start + k < total {
                left[p.start + k] += p.samples[k] * gl
                right[p.start + k] += p.samples[k] * gr
            }
        }
        var peak: Float = 0
        for k in 0..<total { peak = max(peak, abs(left[k]), abs(right[k])) }
        if peak > 0.97 {
            let s = 0.97 / peak
            for k in 0..<total { left[k] *= s; right[k] *= s }
        }
        try StingerMixer.writeWAV(left, right, to: out)
    }
}
