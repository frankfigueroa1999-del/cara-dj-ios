import Foundation

// MARK: - Cara's brain
// What she talks about (segments), how she says it (formats, openings, landings, voice tags),
// how long she talks, and a memory that keeps her from ever saying the same thing twice.

/// What a break is about.
struct Topic {
    var label: String
    var facts: String
    var plain: String? = nil
    var name: String = ""
}

struct Ctx {
    var last: Track?
    var next: Track?
    /// The station's name right now: whatever's playing ("Late Night Drives"), or Non Stop Pop.
    var station: String = Station.fallback
    /// What it's named after, in her words ("the playlist "Late Night Drives"").
    var stationNote: String = ""
    /// The station's old name, when the listener switched to something else since her last break.
    var switchedFrom: String? = nil
    var stationFull: String { Station.full(station) }
}

/// One kind of thing Cara can talk about. Weights decide how often it comes up.
struct Segment {
    let id: String
    let name: String
    let family: String
    let weight: Int
}

enum Brain {
    // MARK: what she can talk about (the flowchart's middle row)
    static let segments: [Segment] = [
        // the music
        Segment(id: "next_intro", name: "Introduce the next song", family: "music", weight: 5),
        Segment(id: "last_verdict", name: "Verdict on the last song", family: "music", weight: 3),
        Segment(id: "trivia", name: "Song trivia", family: "music", weight: 5),
        Segment(id: "artist_story", name: "Artist story", family: "music", weight: 3),
        Segment(id: "time_machine", name: "Time machine (the song's year)", family: "music", weight: 2),
        Segment(id: "your_stats", name: "Your listening habits", family: "music", weight: 3),
        Segment(id: "hot_take", name: "Hot take on the song", family: "music", weight: 2),
        Segment(id: "sing_along", name: "Sing-along dare", family: "music", weight: 1),
        Segment(id: "music_news", name: "Music news", family: "music", weight: 3),
        // your town
        Segment(id: "local_news", name: "Local news", family: "town", weight: 4),
        Segment(id: "weather_now", name: "Weather right now", family: "town", weight: 2),
        Segment(id: "forecast", name: "Today's forecast", family: "town", weight: 2),
        Segment(id: "time_check", name: "Time check", family: "town", weight: 2),
        Segment(id: "day_vibe", name: "Today's vibe (day, season, holidays)", family: "town", weight: 2),
        Segment(id: "hometown", name: "Hometown love", family: "town", weight: 2),
        Segment(id: "traffic_joke", name: "Fake 'traffic report' about your life", family: "town", weight: 1),
        // the world
        Segment(id: "weird_news", name: "Weird world news", family: "world", weight: 3),
        Segment(id: "science", name: "Science news", family: "world", weight: 2),
        Segment(id: "space", name: "Space news", family: "world", weight: 2),
        Segment(id: "tech", name: "Gadgets & tech", family: "world", weight: 2),
        Segment(id: "animals", name: "Animal news", family: "world", weight: 2),
        Segment(id: "food", name: "Food news", family: "world", weight: 2),
        Segment(id: "sports", name: "Sports", family: "world", weight: 1),
        Segment(id: "showbiz", name: "Showbiz gossip", family: "world", weight: 3),
        Segment(id: "screen", name: "Films & TV", family: "world", weight: 2),
        Segment(id: "on_this_day", name: "On this day", family: "world", weight: 2),
        Segment(id: "fun_fact", name: "Fun fact", family: "world", weight: 3),
        Segment(id: "word", name: "Word of the day", family: "world", weight: 1),
        // Cara herself
        Segment(id: "lore", name: "A story from her Los Santos days", family: "cara", weight: 3),
        Segment(id: "confession", name: "A silly confession", family: "cara", weight: 2),
        Segment(id: "opinion", name: "Her unpopular opinion", family: "cara", weight: 2),
        Segment(id: "fake_ad", name: "Fake advert", family: "cara", weight: 3),
        Segment(id: "station_hype", name: "Station hype", family: "cara", weight: 1),
        // you, the listener
        Segment(id: "roast", name: "Playful roast", family: "you", weight: 3),
        Segment(id: "compliment", name: "Backhanded compliment", family: "you", weight: 1),
        Segment(id: "horoscope", name: "Ridiculous horoscope", family: "you", weight: 2),
        Segment(id: "advice", name: "Terrible advice", family: "you", weight: 2),
        Segment(id: "pep_talk", name: "Over-the-top pep talk", family: "you", weight: 2),
        Segment(id: "hypothetical", name: "Picture this…", family: "you", weight: 2),
        // games
        Segment(id: "would_you_rather", name: "Would you rather", family: "games", weight: 2),
        Segment(id: "pop_quiz", name: "Pop quiz", family: "games", weight: 2),
        Segment(id: "debate", name: "Silly debate", family: "games", weight: 2),
        Segment(id: "challenge", name: "Car-safe challenge", family: "games", weight: 1),
    ]

    // MARK: how she says it
    static let formats: [(id: String, how: String)] = [
        ("chat", "Plain, chatty radio talk, like she's telling a mate in the passenger seat."),
        ("breaking", "As an over-the-top BREAKING NEWS bulletin, with fake urgency."),
        ("documentary", "Narrated like a dramatic wildlife documentary."),
        ("commentary", "Like a sports commentator calling it live, building to a big finish."),
        ("trailer", "Like a dramatic movie-trailer voice-over (never say 'in a world')."),
        ("gameshow", "Like a cheesy game-show host, with the listener as today's contestant."),
        ("countdown", "As a quick countdown of three things, from three down to one."),
        ("conspiracy", "Like a silly, harmless conspiracy theory about something tiny and everyday (nothing real or political)."),
        ("posh", "In a very posh, overly formal announcer voice that keeps slipping."),
        ("rhyme", "With a quick, original rhyming couplet in the middle."),
        ("gossip", "Like she's spilling hot gossip to her best friend, giddy and conspiratorial."),
        ("decree", "Like a royal proclamation from Queen Cara of the airwaves."),
        ("forecast", "In the style of a weather forecast, even though it isn't about weather."),
        ("verdict", "Like a judge delivering a dramatic verdict on a silly charge (like 'excessive snoozing')."),
        ("infomercial", "Like a late-night infomercial ('but that's not all!')."),
        ("pilot", "Like a pilot's announcement to the cabin, with the listener as the only passenger."),
        ("selfinterview", "She asks herself a quick question and answers it."),
        ("tourguide", "Like an over-enthusiastic tour guide pointing things out."),
        ("storytime", "As a tiny story with a setup, a twist and a punchline."),
        ("hypeman", "Like a hype person warming up a stadium, all for the listener."),
        ("coach", "Like a fired-up coach giving a half-time pep talk."),
        ("fairytale", "Like a cheerful fairy-tale narrator."),
        ("pirate", "Like an underground pirate-radio DJ broadcasting from a secret location."),
        ("letter", "Like she's reading out a dramatic letter she wrote to the listener."),
    ]

    /// How she opens. `needs`: "" (always fine), "song" (a known song), "last" (the song that just played).
    static let openings: [(id: String, how: String, needs: String)] = [
        ("punchline", "Open with the punchline first, then explain it.", ""),
        ("question", "Open with a question to the listener.", ""),
        ("nickname", "Open by calling the listener a fresh, playful nickname (nothing romantic).", ""),
        ("midthought", "Open mid-thought, as if she's been talking for ages already.", ""),
        ("headline", "Open with a made-up headline of four words or fewer.", ""),
        ("song", "Open with the song or the artist's name.", "song"),
        ("sound", "Open with a sound effect said out loud (like 'ding ding', 'ba-dum-tss', 'bzzt', 'ta-daa'), a new one each time.", ""),
        ("claim", "Open with a bold, ridiculous claim.", ""),
        ("number", "Open with a number.", ""),
        ("town", "Open with the name of the town.", ""),
        ("time", "Open with the time of day or the day of the week.", ""),
        ("confess", "Open with a tiny confession.", ""),
        ("command", "Open with a cheeky order for the listener.", ""),
        ("announce", "Open by introducing herself in a brand-new way.", ""),
        ("verdict", "Open with a one-line verdict on the song that just played.", "last"),
        ("secret", "Open by promising a secret, then actually tell it.", ""),
    ]

    static let endings: [String] = [
        "Bring the next song in by name with a fresh one-line hype.",
        "End on a smug little verdict.",
        "End on a playful threat.",
        "End on a fake apology.",
        "End on a cliffhanger tease about later in the show.",
        "End with a callback to how you opened.",
        "End with a compliment that turns into a tease.",
        "End by giving the listener a silly, car-safe mission for the next song.",
        "End by holding back the next song for one beat of suspense ('...'), then naming it.",
        "End by bragging about the station.",
        "End with a question you don't let them answer.",
        "End with the station's name and a ridiculous made-up line about it, said dead straight as if it's always been the station's motto.",
    ]

    /// Emotion tags the expressive voices understand. Two are suggested per break, never the last ones used.
    /// No nose noises: "snorts" and "chuckles" made her snort and snuffle, so they're gone.
    static let tags: [String] = ["excited", "laughs", "giggles", "sarcastic", "mischievously", "curious", "happy", "surprised"]

    static let persona = """
    Cara is a bubbly, quick-witted British pop DJ who treats the listener like her favourite partner in crime. \
    Playful above everything: puns and wordplay, mock-dramatic overreactions, silly hypotheticals, little games with the listener, \
    cheeky teasing about their habits and taste (always affectionate, like a best mate, never a bully), random tangents that somehow land, \
    and the odd self-own. She's chatty, warm and a bit chaotic: never bored, bitter, mean or preachy. \
    Light British flavour ("proper", "rubbish", "brilliant", "a bit mad", "lovely", "cheeky"), clean language (no swearing).
    """

    /// Her backstory. Non Stop Pop FM is where she made her name in Los Santos; these days her station takes the name of whatever the listener plays.
    static func bible(_ ctx: Ctx) -> String {
        let now = ctx.station == Station.fallback
            ? "worked at a string of terrible stations there, and now broadcasts Non Stop Pop FM to listeners far from the coast"
            : "worked at a string of terrible stations there before making her name on Non Stop Pop FM, and these days runs her own station far from the coast, which always takes the name of whatever the listener puts on"
        return "Her backstory (fixed, never contradict it or add big new facts): she's British, moved to Los Santos years ago chasing fame, \(now). She misses and mocks Los Santos in equal measure (Vinewood, Vespucci Beach, Del Perro Pier, Rockford Hills, Sandy Shores, Mount Chiliad, the endless freeway traffic), and only ever talks about it as a place from her past."
    }

    /// What the station's called right now, and how she uses the name.
    static func stationLine(_ ctx: Ctx) -> String {
        if ctx.station == Station.fallback { return "THE STATION: Non Stop Pop FM." }
        let from = ctx.stationNote.isEmpty ? "\"\(ctx.station)\"" : ctx.stationNote
        return "THE STATION: it's named after whatever the listener is playing, which right now is \(from), so on air it's \"\(ctx.stationFull)\". Use the name when it fits (dropping it in like a real DJ, bragging about it, a cheeky comment on the name), not in every break. Never call it Non Stop Pop: that was her old station, back in Los Santos."
    }

    static let rules = """
    RULES (all of them, every time):
    - Only use the facts you're given. Never invent news, names, numbers, quotes or claims about real people or real places. Made-up silliness is fine only when it's obviously a joke (a fake advert, a hypothetical, a horoscope).
    - Never mention death or dying in any form, not even as a figure of speech (no "died", "dead", "killing it", "RIP"), and nothing about anyone being hurt, ill, missing, arrested or in trouble.
    - No politics, wars, religion, crime or tragedies. Never mock anyone's looks, body, race, gender, sexuality, religion or disability.
    - Never sigh (no "sigh" or "[sighs]"), never snort, sniff or make any nose noise, never start with "Shh" or hush the listener, never open with Oh, Ooh, Ah, Whoa, Woah or Wow, and never write "gasp".
    - Never comment on the music stopping or on silence.
    - Never say the words "slogan" or "tagline", and never name what you're doing ("here's my dramatic pause", "station ID"): just say the line itself.
    - Skip the tired stuff: phones, social media, dancing, drinking water, "buckle up", "let's go", "you're welcome", "chef's kiss", "iconic".
    - No recurring invented characters (no named friends, callers, exes or colleagues).
    - The listener may be driving: any challenge must be voice-only and safe (eyes on the road, hands on the wheel).
    - Never quote song lyrics.
    - Spell numbers the way people say them ("fifty-nine degrees", "four seventeen").
    - Write for the ear: contractions, fragments, natural pauses with commas, dashes or "...". No emojis, hashtags, asterisks or stage directions (only the voice tags allowed below).
    - Write ONLY the words Cara says out loud.
    """

    // MARK: things to talk about (each list is used up before anything repeats)
    static let lore: [String] = [
        "The time she got stuck at the top of the Ferris wheel on Del Perro Pier for forty minutes and did a live weather report to the people in the next carriage.",
        "The time a stranger in Vinewood insisted she was a famous actress and she let them believe it for an entire dinner.",
        "The time she tried to hike Mount Chiliad in the wrong shoes, gave up halfway, and got a lift down from a very quiet man with a goat.",
        "The time she crossed the Grand Senora Desert in a car with no air-con and a playlist she regrets.",
        "The time she got lost in Sandy Shores looking for a decent cup of tea and found a bar that served it in a trainer.",
        "The time a seagull stole her lunch on Vespucci Beach and she swore revenge, then saw it again the next week.",
        "The time she was stuck in Los Santos freeway traffic for so long she finished an entire audiobook.",
        "The time she went rollerblading on the Vespucci boardwalk and commentated the whole thing like a live sports event.",
        "The time she accidentally walked into a Rockford Hills yoga class and stayed for the full hour out of pride.",
        "The time she auditioned for a Vinewood film and her entire role was 'woman who looks at a bus'.",
        "The time a waiter at a rooftop restaurant recognised her as 'the radio woman who is always complaining'.",
        "The time she got a free ticket to a Vinewood premiere and spent it hiding behind a potted palm to avoid the cameras.",
        "The time she rented a convertible in Los Santos and put the roof down just as the heavens opened.",
        "The time her flat's air-con broke in a heatwave and she did a whole radio shift sitting in a paddling pool.",
        "The time she went to a Los Santos self-help seminar and got asked to leave for heckling the speaker, lovingly.",
        "The time she tried surfing off Vespucci Beach and the only thing she caught was a stranger's cool box.",
        "The time she drove up to the Vinewood sign at dawn for 'inspiration' and ended up eating a sad sandwich in the car.",
        "The time she moved to Los Santos with two suitcases, big dreams and the wrong plug adaptor.",
        "The time she entered a hot-dog eating contest on Del Perro Pier, retired after one bite, and commentated the rest.",
        "The time she got locked out of a Vinewood studio in her dressing gown and did the breakfast show from the car park.",
        "The time she bought a 'vintage' surfboard in Vespucci that turned out to be an ironing board.",
        "The time she joined a Rockford Hills book club that never once discussed a book, only the snacks.",
        "The time she took a Vinewood celebrity-homes bus tour and the only famous thing she saw was a famous traffic jam.",
        "The time she hosted a pub quiz in Mirror Park and got every answer on her own answer sheet wrong.",
        "The time she adopted a cactus in Sandy Shores and it got more fan mail at the station than she did.",
        "The time she ordered a smoothie at a Los Santos juice bar that was, as far as she could tell, mostly lawn.",
        "The time she got a parking ticket outside her own radio station on her very first day.",
        "The time she tried paddleboarding on the Alamo Sea and paddled in a perfect circle for half an hour.",
        "The time a tour group at the Vinewood sign made her take their photo forty times and never offered to take hers.",
        "The time she built a sandcastle radio studio at Vespucci Beach and the tide reviewed it harshly.",
        "The time a posh Rockford Hills restaurant served portions so tiny she stopped for chips on the way home.",
        "The time she won karaoke night in Vespucci with a power ballad, full key change, while holding a hot dog.",
        "The time a talent scout in Vinewood said she had 'a great face for radio' and she took it as a compliment for a week.",
        "The time she rode a tandem bike along the Del Perro boardwalk with a stranger who wouldn't stop pedalling backwards.",
        "The time she tried to go 'off grid' near Paleto Bay and lasted until her first craving for a proper cup of tea.",
        "The time she went fishing off Paleto Bay and caught one sock, which she still keeps for luck.",
        "The time she volunteered at a Los Santos dog show and got upstaged by a poodle in a bow tie.",
        "The time she camped on Mount Chiliad and a raccoon strolled off with her marshmallows like he'd paid for them.",
        "The time she got her hair done in Vinewood and walked out looking like a very confident pineapple.",
        "The time she DJed a Rockford Hills wedding, played completely the wrong first song, and they loved it more.",
        "The time she got lost inside a Los Santos shopping mall and only found the exit after buying three candles.",
        "The time she fell asleep on a Vespucci sun lounger and woke up with a tan line shaped like her sunglasses.",
        "The time she tried learning the ukulele on Del Perro Pier and a busker paid her to stop.",
        "The time she entered a chilli cook-off in Sandy Shores and her entry was voted 'most like soup'.",
        "The time she tried to be a morning person in Los Santos and lasted exactly one sunrise.",
    ]

    static let confessions: [String] = [
        "she can't whistle, no matter how hard she tries",
        "she has never once parallel parked on the first go",
        "she still can't fold a fitted sheet and has decided it's a myth",
        "she talks to her houseplants and is fairly sure they gossip about her",
        "she's genuinely scared of geese",
        "she practises award acceptance speeches in the shower",
        "she names every car she's ever owned",
        "she can't wink, she just blinks dramatically with both eyes",
        "she secretly loves lift music",
        "she cannot open a bag of crisps without it exploding everywhere",
        "she has a playlist just for doing the washing up",
        "she pretends to know about wine and just says 'oaky' a lot",
        "she has never finished a jigsaw puzzle",
        "she once lost an argument with a self-checkout machine",
        "she waves back at people who were waving at someone behind her",
        "she reads the last page of a book first",
        "she laughs at her own jokes before she reaches the punchline",
        "she keeps a drawer full of mystery cables she'll never use",
        "she has a gym nemesis who has no idea",
        "she sleeps with socks on all year round",
        "she once went round a revolving door twice because she panicked",
        "she ranks biscuits, and the rankings are final",
        "she owns more mugs than plates",
        "she says 'you too' when a waiter tells her to enjoy her meal",
        "she reheats the same cup of tea four times a day",
        "she claps when films end, even at home",
        "she keeps buying notebooks and never writes in them",
        "she can't say 'squirrel' quickly without tripping over it",
        "she still sets six alarms every morning",
        "she gives her car a pep talk on cold mornings",
    ]

    static let opinions: [String] = [
        "Is a hot dog a sandwich?",
        "Is cereal technically a soup?",
        "Does pineapple belong on pizza?",
        "Milk in first or tea in first?",
        "Toilet roll: over or under?",
        "Are socks with sandals secretly a power move?",
        "Is water wet?",
        "Is a Jaffa Cake a cake or a biscuit?",
        "Should ketchup live in the fridge or the cupboard?",
        "Is breakfast for dinner the best dinner?",
        "Is a burrito just a very confident wrap?",
        "Are naps a sign of genius?",
        "Is it acceptable to clap when a plane lands?",
        "Morning shower or night shower?",
        "Cats or dogs, final answer?",
        "How many holes does a straw have?",
        "Who owns the middle armrest?",
        "Kit Kat: snap it or bite it?",
        "Pancakes or waffles?",
        "Is it too early for festive music in October?",
        "Is a bagel just a doughnut with a serious job?",
        "Crunchy or smooth peanut butter?",
        "Is it 'gif' or 'jif'?",
        "Are crusts the best bit of the sandwich?",
        "Should the toast be cut in triangles or rectangles?",
        "Is the last chip in the bag lucky or cursed?",
        "Is a smoothie a drink or a meal?",
        "Should you make your bed if you're getting back in it later?",
    ]

    static let fakeAds: [String] = [
        "SnoozeShield: a hat that plays your alarm only to you, so you can ignore it in private.",
        "Bluffington's Instant Expertise Spray: one spritz and you can talk confidently about wine.",
        "PetRock Pro: the premium pet rock, now with a monthly subscription.",
        "LoungeLord: a sofa with a built-in snack drawer and absolutely zero judgement.",
        "Nope Juice: the energy drink that gives you just enough energy to cancel your plans.",
        "The Gourmet Toast Academy: a twelve-week course in toast.",
        "SockMatch: finds your missing socks, or emotionally prepares you to move on.",
        "Crunchtastic Unbreakable Crisps: the crisp that refuses to snap.",
        "LawnLord: a robotic garden gnome that judges your mowing.",
        "Spa Day in a Can: just open it and pretend.",
        "The Procrastinator Three Thousand: a calendar that only ever shows tomorrow.",
        "Sandy Shores Luxury Gravel: hand-picked, slightly warm.",
        "Mount Chiliad Mountain Air, freshly bottled in a jam jar.",
        "Rockford Hills Premium Ice Cubes, individually gift-wrapped.",
        "Vespucci Beach Sand, now with forty percent fewer seagulls.",
        "Vinewood Celebrity Breath Mints: smell like you've been famous.",
        "Del Perro Pier Candyfloss Perfume.",
        "The Parallel Parking Coach: a little voice that just shouts 'commit!'",
        "The Clap-On Fridge Light.",
        "NapPods: soundproof helmets for napping in public.",
        "Bubble Wrap Pyjamas: pop yourself to sleep.",
        "The Self-Stirring Mug, for people too important to stir.",
        "The Thermostat Peace Treaty: a lockable thermostat cover for households that can't agree.",
        "The Karaoke Shower Head, with built-in applause.",
        "Mood-Ring Car Paint.",
        "Instant Patience Tablets (do not take while queueing).",
        "Fancy Water: tap water, but with a French accent.",
        "Big Talk Cards: conversation starters that skip straight to aliens.",
        "The Dramatic Entrance Smoke Machine, for your front door.",
        "The Snack Hoodie: a hoodie with a secret crisp pocket.",
        "Guilt-Free Cake: it's a cake, but it apologises.",
        "Luxury Bubble Bath for your car.",
        "The Sock Sommelier: pairs your socks by mood.",
        "The Excuse Generator: a little box that prints a fresh excuse every morning.",
        "Gourmet Ice for Fancy Occasions: it's ice, but the box is gold.",
        "The Leftover Locator: finds the takeaway you forgot in the back of the fridge.",
        "Silent Crisps, for eating in the cinema.",
        "Motivational Doormat: shouts encouragement every time you step on it.",
        "The Plant Whisperer: a speaker that compliments your houseplants while you're out.",
        "Portable Sunshine: a lamp that tells you it's Friday.",
    ]

    static let roasts: [String] = [
        "Roast the listener's music taste, then admit grudgingly that this one is good.",
        "Call out something the listener is probably doing right now (procrastinating, still in pyjamas, eating something they said they wouldn't) with a playful put-down.",
        "Be fake-wounded: the listener only shows up for the hits and never says thank you.",
        "Mock the listener's habit of replaying one song forty times in a row.",
        "Be smug about being the only voice of reason on the station, then undercut it.",
        "Pay the listener a deadpan compliment that's obviously a tease.",
        "Scold the listener like a disappointed aunt, then forgive them by the next song.",
        "Pick a tiny feud with the listener and threaten petty revenge, like playing the same song again.",
        "Grumble that the artist gets all the credit while she does all the talking.",
        "Tease the listener's excuses: 'I was just about to', 'five more minutes', 'it's not my fault'.",
        "Tease the listener about the five songs they secretly have on repeat.",
        "Tease the listener for pretending to know all the words.",
        "Tease the listener's 'I'll start on Monday' plans.",
        "Tease the listener's 'one more song' promise that always becomes ten.",
        "Tease the listener's snooze-button habit.",
        "Tease the listener's junk drawer and everything living in it.",
        "Tease the listener's dramatic reaction to a light drizzle.",
        "Tease the listener for talking to their pet in a baby voice.",
        "Tease the listener for rehearsing arguments in the shower.",
        "Tease the listener's 'healthy snack' that is definitely just biscuits.",
        "Tease the listener for always being 'five minutes away'.",
        "Tease the listener's karaoke song choice.",
        "Tease the listener's 'quick nap' that lasted three hours.",
        "Tease the listener's fridge, which contains one lemon and a vibe.",
        "Tease the listener's sense of direction.",
        "Tease the listener's bag full of other bags.",
        "Tease the listener's 'I'll remember that' instead of writing it down.",
        "Tease the listener's ever-growing pile of things they'll 'get round to'.",
        "Tease the listener for clapping when the plane lands.",
        "Tease how long the listener takes to choose something to watch.",
    ]

    static let wouldYouRather: [String] = [
        "have spaghetti for hair or sweat maple syrup",
        "only be able to whisper or only be able to shout",
        "have a rewind button or a pause button for your life",
        "speak every language or play every instrument",
        "always have a song stuck in your head or never hear a new song again",
        "have a personal theme song when you walk into a room or a laugh track for your life",
        "live in a house made of cheese or drive a car made of chocolate",
        "talk to animals or speak every human language",
        "give up sandwiches forever or give up crisps forever",
        "always be ten minutes late or always be twenty minutes early",
        "sneeze glitter or burp bubbles",
        "have a cat the size of a dinosaur or a dinosaur the size of a cat",
        "only eat breakfast food forever or never eat breakfast food again",
        "be the funniest person in the room or the smartest",
        "have unlimited free flights or unlimited free food",
        "fly, but only at walking pace, or teleport, but only three feet at a time",
        "burst into a musical number every time you speak or have a narrator for your whole life",
        "have hiccups forever or always feel like you're about to sneeze",
        "swap lives for a day with your pet or with your favourite pop star",
        "never use a microwave again or never use a toaster again",
        "listen to one song forever or never hear the same song twice",
        "be followed everywhere by a rubber chicken or by a tuba player",
        "have a rocket-powered shopping trolley or a hovercraft sofa",
        "always smell of popcorn or always smell of fresh laundry",
        "do karaoke every night or never again",
        "wear socks with sandals forever or a suit to the beach forever",
        "pause time or rewind it ten seconds",
        "have a pet dragon or be a dragon",
        "be famous for something silly or unknown for something brilliant",
        "speak only in questions or only in rhymes",
        "have every traffic light turn green for you or always find a parking spot",
        "get the giggles at serious moments or cry at every advert",
        "eat a whole lemon or drink a glass of pickle juice",
        "live in a treehouse or a houseboat",
        "have a robot butler or a robot best friend",
        "know every song's lyrics perfectly or be able to hit every high note",
    ]

    static let dilemmas: [String] = [
        "There's one slice of pizza left in the shared fridge and it isn't theirs.",
        "They waved at someone who wasn't waving at them.",
        "They've said 'pardon' three times and still didn't catch it.",
        "They poured the cereal and then discovered there's no milk.",
        "Their houseplant is clearly unhappy with them.",
        "They've forgotten the name of someone they've known for a year.",
        "A song has been stuck in their head for three days.",
        "They told the hairdresser they love it, and they don't.",
        "The group plan has been 'we should totally' for six months.",
        "They have exactly one clean sock.",
        "Their toast landed butter side down.",
        "They said 'you too' when someone wished them happy birthday.",
        "They've been calling someone the wrong name for too long to fix it.",
        "There's a mystery container at the back of the fridge.",
        "They can't decide what to have for tea.",
        "They popped to the shop for milk and came back with a lamp.",
        "Their sat-nav voice sounds disappointed in them.",
        "They agreed to help a mate move house this weekend.",
        "They've lost the TV remote inside the sofa again.",
        "They're the last one at the table and the bill just arrived.",
    ]

    static let challenges: [String] = [
        "Hum the bass line of the next song.",
        "Rate the next song out of ten, out loud, like a talent-show judge.",
        "Guess the year the next song came out before the chorus.",
        "Invent a brand-new title for the next song.",
        "Count how many times the singer says the song's title.",
        "Sing the next chorus in your best opera voice.",
        "Say one genuinely nice thing about yourself out loud, right now.",
        "Beatbox the intro of the next song.",
        "Narrate the next thirty seconds of your life like a nature documentary.",
        "Pick who'd play you in the film of your life, out loud.",
        "Hum the next tune in the voice of a very posh cat.",
        "Give the next song a star sign.",
        "Name three songs with a colour in the title before the first chorus.",
        "Make up a jingle for your favourite snack.",
        "Sing the next chorus like it's the last night of a world tour.",
        "Commentate whatever you do next like it's a sports final.",
        "Guess the next song's artist before they start singing.",
        "Do your best trumpet impression on the next big moment.",
    ]

    static let pepTalks: [String] = [
        "doing the laundry", "that email they've been avoiding", "eating a vegetable on purpose",
        "getting out of bed tomorrow", "the weekly food shop", "tidying the car",
        "finally returning the thing they borrowed", "trying a new recipe", "going to the gym",
        "cleaning the oven", "booking that dentist appointment", "making the bed",
        "watering the plants", "going for a walk", "learning a new skill", "parking perfectly",
        "unloading the dishwasher", "replying to that invitation",
    ]

    static let hypotheticals: [String] = [
        "the listener has been made mayor of the town for one day",
        "the listener takes over the station as DJ for exactly one minute",
        "the listener's life suddenly has a laugh track",
        "a seagull has become the listener's manager",
        "the listener has been cast in a music video with a budget of five pounds",
        "the listener is on a cooking show and only has crisps and a lemon",
        "the listener's car has started giving them life advice",
        "the listener has been crowned world champion of something tiny",
        "the listener's fridge has started writing poetry",
        "the listener opens a café that only serves toast",
        "the listener's shadow goes on holiday without them",
        "the next song is officially the theme tune of the listener's life",
        "the listener has won a lifetime supply of something completely useless",
        "the listener's pet starts its own podcast",
        "the listener is on a game show about their own life",
        "the listener's sofa has its own fan club",
        "the listener invents a brand-new holiday",
        "every time the listener sneezes, confetti comes out",
        "the listener has to pick a walk-on song for everywhere they go",
        "the listener becomes the face of a cereal box",
    ]

    static let quiz: [(q: String, a: String)] = [
        ("What's the only food that never goes off?", "honey"),
        ("How many hearts does an octopus have?", "three"),
        ("What's the biggest planet in our solar system?", "Jupiter"),
        ("What's the smallest country in the world?", "Vatican City"),
        ("What colour is a polar bear's skin?", "black"),
        ("How many strings does a standard guitar have?", "six"),
        ("What's the hardest natural substance?", "diamond"),
        ("Which planet is called the Red Planet?", "Mars"),
        ("How many keys does a standard piano have?", "eighty-eight"),
        ("What's the main ingredient in guacamole?", "avocado"),
        ("Which is the biggest ocean?", "the Pacific"),
        ("How many bones are in an adult human body?", "two hundred and six"),
        ("What's the tallest animal?", "the giraffe"),
        ("What's the capital of Australia?", "Canberra"),
        ("How many minutes are there in a day?", "one thousand, four hundred and forty"),
        ("What's a baby kangaroo called?", "a joey"),
        ("How many sides does a hexagon have?", "six"),
        ("What fruit do raisins come from?", "grapes"),
        ("What's the fastest land animal?", "the cheetah"),
        ("Who painted the Mona Lisa?", "Leonardo da Vinci"),
        ("What's the chemical symbol for gold?", "Au"),
        ("How many players does a football team have on the pitch?", "eleven"),
        ("What's the largest mammal on Earth?", "the blue whale"),
        ("What's a group of lions called?", "a pride"),
        ("At what temperature does water freeze, in Fahrenheit?", "thirty-two degrees"),
        ("How many colours are in a traditional rainbow?", "seven"),
        ("Which planet has the most moons?", "Saturn"),
        ("What do caterpillars turn into?", "butterflies or moths"),
        ("Which bird is the classic symbol of peace?", "the dove"),
        ("What's the name of the fairy in Peter Pan?", "Tinker Bell"),
        ("How many legs does a spider have?", "eight"),
        ("Which instrument has black and white keys and hammers inside?", "the piano"),
    ]

    static let funFacts: [String] = [
        "Honey never goes off: edible honey has been found in ancient Egyptian tombs.",
        "Octopuses have three hearts and blue blood.",
        "Botanically speaking, bananas are berries and strawberries aren't.",
        "A day on Venus is longer than its whole year.",
        "Wombat poo comes out cube-shaped.",
        "Sharks have been around longer than trees.",
        "The Eiffel Tower can grow about fifteen centimetres taller in summer because the metal expands in the heat.",
        "A group of flamingos is called a flamboyance.",
        "Sea otters hold hands while they sleep so they don't drift apart.",
        "Scotland's national animal is the unicorn.",
        "Butterflies taste with their feet.",
        "The dot over a lowercase i or j is called a tittle.",
        "A pineapple takes about two years to grow.",
        "Koalas can sleep up to twenty hours a day.",
        "Early cultivated carrots were purple and yellow; orange ones came later.",
        "A fluffy cumulus cloud can weigh around half a million kilos.",
        "Venus spins the opposite way to most planets.",
        "There are more possible games of chess than atoms in the observable universe.",
        "A bolt of lightning is about five times hotter than the surface of the Sun.",
        "Some penguins give their partners pebbles to help build a nest.",
        "'Rhythms' is the longest common English word with no a, e, i, o or u.",
        "A jiffy is an actual unit of time.",
        "Bubble wrap was first invented as a textured wallpaper.",
        "The microwave oven was invented after an engineer noticed a chocolate bar melting in his pocket near radar equipment.",
        "Play-Doh was first sold as a wallpaper cleaner.",
        "The first product ever scanned with a barcode was a pack of chewing gum.",
        "Astronauts can come back a few centimetres taller because their spines stretch out in space.",
        "You can't hum while holding your nose.",
        "A shrimp's heart is in its head.",
        "Hippos can't actually swim; they bounce along the bottom.",
        "Cats can't taste sweet things.",
        "Dolphins use signature whistles that work a bit like names.",
        "Crows can recognise individual human faces.",
        "Apples float because they're about a quarter air.",
        "Peanuts aren't nuts; they're legumes, like peas.",
        "A strawberry has around two hundred seeds on the outside.",
        "A 'moment' was a medieval unit of time lasting about ninety seconds.",
        "Koala fingerprints are so similar to ours they're hard to tell apart.",
        "Some turtles can breathe through their bums.",
        "Sloths can hold their breath longer than dolphins can.",
        "Bees can learn to recognise human faces.",
        "In the world's quietest rooms you can hear your own heartbeat.",
        "Your stomach gets a fresh lining every few days.",
        "Goats have rectangular pupils.",
        "One piece of spaghetti is called a spaghetto.",
        "Kangaroos can't easily walk backwards.",
        "The Moon drifts about four centimetres further from Earth every year.",
        "A teaspoon of neutron star would weigh billions of tonnes.",
        "Ketchup was sold as a medicine in the eighteen-thirties.",
        "One of the first alarm clocks could only ring at four in the morning.",
        "From a plane, a rainbow can look like a full circle.",
        "Nintendo started out making playing cards back in eighteen eighty-nine.",
        "The Hollywood sign originally said 'Hollywoodland'.",
        "The world's shortest scheduled flight, between two Scottish islands, takes about a minute and a half.",
        "Sea otters keep a handy rock in a pouch of loose skin under their arm.",
        "A group of owls is called a parliament.",
    ]

    static let words: [(w: String, m: String)] = [
        ("petrichor", "the earthy smell after rain falls on dry ground"),
        ("defenestration", "the act of throwing something out of a window"),
        ("lollygag", "to dawdle and waste time"),
        ("kerfuffle", "a commotion or fuss"),
        ("discombobulated", "confused and flustered"),
        ("gobbledygook", "language that's complete nonsense"),
        ("brouhaha", "a noisy, overexcited reaction"),
        ("flibbertigibbet", "a flighty, chattering person"),
        ("hullabaloo", "a big noisy fuss"),
        ("cattywampus", "askew or out of line"),
        ("bumfuzzle", "to confuse someone"),
        ("collywobbles", "butterflies in your stomach"),
        ("skedaddle", "to run off in a hurry"),
        ("widdershins", "anticlockwise"),
        ("gubbins", "bits and pieces, odds and ends"),
        ("hornswoggle", "to trick or swindle"),
        ("absquatulate", "to leave suddenly"),
        ("argle-bargle", "copious, meaningless talk"),
        ("shenanigans", "mischief"),
        ("nincompoop", "a silly person"),
        ("whippersnapper", "a cheeky young upstart"),
        ("serendipity", "a happy accident"),
        ("ultracrepidarian", "someone who gives opinions on things they know nothing about"),
        ("quidnunc", "a nosy gossip"),
        ("borborygmus", "the rumbling of a hungry stomach"),
        ("apricity", "the warmth of the sun in winter"),
        ("gongoozler", "someone who idly watches boats on a canal"),
        ("mumpsimus", "someone who sticks to a mistake out of stubbornness"),
    ]

    static let signs: [String] = ["Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo", "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"]

    static let yakima: [String] = [
        "The Yakima Valley grows roughly three-quarters of all the hops in the United States.",
        "Washington grows more apples than any other US state, and the Yakima Valley is a big part of that.",
        "There's a famous old sign welcoming people to Yakima as 'the Palm Springs of Washington'.",
        "The Yakima Valley became Washington's very first official wine region, back in nineteen eighty-three.",
        "Locals love to brag about getting around three hundred days of sunshine a year.",
        "The Central Washington State Fair happens in Yakima every autumn.",
        "On a clear day you can spot Mount Rainier and Mount Adams from around the valley.",
        "The Yakima Valley grows loads of cherries, pears and grapes too.",
    ]

    static let holidays: [String: String] = [
        "01-01": "New Year's Day", "02-09": "National Pizza Day in the US", "02-14": "Valentine's Day",
        "03-14": "Pi Day", "03-17": "St Patrick's Day", "04-01": "April Fools' Day", "04-22": "Earth Day",
        "05-04": "Star Wars Day", "07-04": "Independence Day in the US", "08-08": "International Cat Day",
        "08-26": "National Dog Day in the US", "09-19": "International Talk Like a Pirate Day",
        "10-01": "International Coffee Day", "10-04": "National Taco Day in the US", "10-31": "Halloween",
        "11-05": "Bonfire Night back in England", "11-13": "World Kindness Day", "12-24": "Christmas Eve",
        "12-25": "Christmas Day", "12-26": "Boxing Day", "12-31": "New Year's Eve",
    ]

    // MARK: pop-ins (a quick drop-in a few seconds into a song)
    static let popinKinds: [(id: String, how: String)] = [
        ("name_quip", "Say the song name, then one quick quip about the title or the artist's name."),
        ("rating", "Say the song name, then rate it on a ridiculous scale you invent on the spot."),
        ("tease", "Say the song name, then tease the listener for how much they're clearly enjoying it."),
        ("dare", "Say the song name, then dare the listener to do something silly but car-safe (voice only) during it."),
        ("vibe", "Say the song name, then describe its vibe as a weird, specific image (what weather, snack or outfit it is)."),
        ("callback", "Say the song name, then make a quick callback to the last thing you talked about."),
        ("hype", "Introduce the song like a stadium announcer introducing a champion."),
        ("fact", "Say the song name, then drop ONE real fact from the text below, in your own words."),
    ]
}

// MARK: - Memory (kept on the phone, so she never repeats herself, even after the app restarts)
@MainActor
final class CaraMemory {
    static let shared = CaraMemory()

    struct Store: Codable {
        var breaks: [String] = []
        var segments: [String] = []
        var formats: [String] = []
        var openings: [String] = []
        var endings: [String] = []
        var tags: [String] = []
        var popins: [String] = []
        var facts: [String: Double] = [:]
        var used: [String: [Int]] = [:]
    }

    private(set) var s = Store()
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("cara-memory.json")
        if let data = try? Data(contentsOf: url), let st = try? JSONDecoder().decode(Store.self, from: data) { s = st }
    }

    func save() {
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: url, options: .atomic) }
    }

    var recent: [String] { s.breaks }
    var lastBreak: String? { s.breaks.last }

    /// Picks an item from a list that hasn't been used yet (the list resets once she's been through all of it).
    func fresh<T>(_ name: String, _ list: [T]) -> T {
        var used = Set(s.used[name] ?? [])
        if used.count >= list.count { used = [] }
        let left = list.indices.filter { !used.contains($0) }
        let i = left.randomElement() ?? 0
        used.insert(i)
        s.used[name] = Array(used)
        return list[i]
    }

    /// A headline or fact she hasn't used in the last few days.
    func isFresh(_ key: String, days: Double = 3) -> Bool {
        guard let t = s.facts[key.lowercased()] else { return true }
        return Date().timeIntervalSince1970 - t > days * 86400
    }

    func markUsed(_ key: String) {
        s.facts[key.lowercased()] = Date().timeIntervalSince1970
        let cutoff = Date().timeIntervalSince1970 - 14 * 86400
        s.facts = s.facts.filter { $0.value > cutoff }
    }

    /// The ids used most recently in one of the lists (segments, formats, openings, endings, tags, pop-ins).
    func last(_ kind: String, _ n: Int) -> [String] {
        let all: [String]
        switch kind {
        case "segments": all = s.segments
        case "formats": all = s.formats
        case "openings": all = s.openings
        case "endings": all = s.endings
        case "tags": all = s.tags
        default: all = s.popins
        }
        return Array(all.suffix(n))
    }

    func remember(text: String, segment: String?, format: String?, opening: String?, ending: String?, tags: [String], popin: String?) {
        s.breaks.append(text)
        if s.breaks.count > 80 { s.breaks.removeFirst(s.breaks.count - 80) }
        func push(_ arr: inout [String], _ v: String?, keep: Int) {
            guard let v = v, !v.isEmpty else { return }
            arr.append(v)
            if arr.count > keep { arr.removeFirst(arr.count - keep) }
        }
        push(&s.segments, segment, keep: 40)
        push(&s.formats, format, keep: 20)
        push(&s.openings, opening, keep: 20)
        push(&s.endings, ending, keep: 20)
        push(&s.popins, popin, keep: 20)
        for t in tags { push(&s.tags, t, keep: 12) }
        save()
    }
}

// MARK: - Repeat detection
enum Repeats {
    static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "for", "with", "is", "it", "it's", "that", "this",
        "you", "your", "you're", "i", "i'm", "me", "my", "we", "be", "are", "was", "so", "just", "like", "up", "out", "now",
        "all", "get", "got", "do", "don't", "can", "not", "no", "what", "who", "how", "its", "that's", "there", "here",
        "they", "them", "he", "she", "his", "her", "as", "if", "then", "than", "from", "by", "about", "into", "off", "over",
        "one", "right", "okay", "well", "yeah", "oh", "have", "has", "had", "will", "would", "could", "this", "these", "those",
    ]

    static func words(_ t: String) -> [String] {
        let noTags = t.lowercased().replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        return noTags.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") }).map(String.init)
    }

    static func grams(_ w: [String], _ n: Int, skip: Set<String>) -> Set<String> {
        guard w.count >= n else { return [] }
        var out = Set<String>()
        for i in 0...(w.count - n) {
            let g = Array(w[i..<(i + n)])
            if g.allSatisfy({ stopWords.contains($0) }) { continue }
            if g.contains(where: { skip.contains($0) }) { continue }
            out.insert(g.joined(separator: " "))
        }
        return out
    }

    /// The first two words of a line, for spotting repeated openings.
    static func opener(_ t: String) -> String {
        words(t).prefix(2).joined(separator: " ")
    }

    /// Phrases she's leaned on in more than one recent break.
    static func wornOut(_ recent: [String], skip: Set<String>) -> [String] {
        var count: [String: Int] = [:]
        for r in recent.suffix(40) {
            for g in grams(words(r), 3, skip: skip) { count[g, default: 0] += 1 }
        }
        return count.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.prefix(30).map { $0.key }
    }

    /// Why a draft can't be used (nil when it's fine).
    /// "Slogan" and friends: words that only show up when she reads out what she was asked to do.
    static func saysLabel(_ text: String) -> String? {
        words(text).first { ["slogan", "slogans", "tagline", "taglines"].contains($0) }
    }

    static func problem(_ text: String, recent: [String], skip: Set<String>) -> String? {
        let w = words(text)
        if w.isEmpty { return "It was empty." }
        if mentionsDeath(text) { return "It mentioned death or dying (even as a figure of speech). Leave that out completely." }
        let first = w.first ?? ""
        if ["whoa", "woah", "wow", "oh", "ooh", "ah", "shh", "shhh"].contains(first) { return "It opened with '\(first)'. Open with a real word instead." }
        if w.contains("gasp") || w.contains("sigh") || w.contains("sighs") { return "It used 'gasp' or 'sigh'. Leave those out." }
        if w.contains(where: { $0.hasPrefix("snort") || $0.hasPrefix("sniff") }) { return "It had a snort or a sniff in it. Leave nose noises out completely." }
        if let label = saysLabel(text) { return "It said the word '\(label)'. Never call anything a slogan or tagline: just say the line itself." }
        let open = opener(text)
        let recentOpeners = recent.suffix(30).map { opener($0) }
        if !open.isEmpty && recentOpeners.contains(open) { return "It opened with \"\(open)\", which you've used before. Open completely differently." }
        if let lastFirst = recent.suffix(6).compactMap({ words($0).first }).first(where: { $0 == first }), !lastFirst.isEmpty {
            return "It started with the same first word (\"\(first)\") as a recent break. Start differently."
        }
        let mine = grams(w, 4, skip: skip)
        for r in recent.suffix(40) {
            if let hit = mine.intersection(grams(words(r), 4, skip: skip)).first {
                return "It reused the phrase \"\(hit)\" from an earlier break. Say it in completely new words."
            }
        }
        return nil
    }
}

// MARK: - Gathering something to talk about
private func songFacts(_ t: Track, when: String) -> String {
    var f = "\(when) song is \"\(t.title)\" by \(t.artist)"
    if !t.album.isEmpty { f += ", from the album \"\(t.album)\"" }
    if !t.year.isEmpty { f += " (\(t.year))" }
    return f + ". Use only these facts about it (the album or year are fine), never claim anything else about the artist or song."
}

/// Today's high, low and chance of rain.
func getForecast(lat: Double, lon: Double) async -> (high: Int, low: Int, rain: Int)? {
    guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=fahrenheit&timezone=auto&forecast_days=1"),
          let data = await fetchData(url, timeout: 8),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let d = j["daily"] as? [String: Any],
          let hi = (d["temperature_2m_max"] as? [Double])?.first,
          let lo = (d["temperature_2m_min"] as? [Double])?.first else { return nil }
    let rain = (d["precipitation_probability_max"] as? [Double])?.first ?? 0
    return (Int(hi.rounded()), Int(lo.rounded()), Int(rain.rounded()))
}

/// Something light that happened on today's date (Wikipedia), never anything dark.
func onThisDay() async -> [String] {
    let f = DateFormatter()
    f.dateFormat = "MM/dd"
    guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/feed/onthisday/events/" + f.string(from: Date())),
          let data = await fetchData(url, timeout: 8),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let events = j["events"] as? [[String: Any]] else { return [] }
    let light = #"\b(?:album|song|single|band|film|movie|television|tv|series|premiere|premiered|released|launch|launched|record|game|video game|invented|opened|first|festival|concert|chart|toy|cartoon|comic|museum|zoo|park|space|satellite|moon|computer|internet|website)\b"#
    var out: [String] = []
    for e in events {
        guard let text = e["text"] as? String, let year = e["year"] as? Int else { continue }
        guard text.count < 240, isSafe(text), !mentionsDeath(text) else { continue }
        guard text.range(of: light, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
        out.append("On this day in \(year): \(text)")
    }
    return out
}

@MainActor
private func freshHeadline(_ feeds: [String], extra: String? = nil) async -> String? {
    let h = await getHeadlines(feeds, extra: extra)
    let mem = CaraMemory.shared
    guard let pickOne = h.filter({ mem.isFresh($0) }).randomElement() else { return nil }
    mem.markUsed(pickOne)
    return pickOne
}

private func feed(_ q: String) -> String { gnews(q) }

/// Builds the facts for one segment. nil when there's nothing usable right now (she picks something else).
@MainActor
func topicFor(_ id: String, ctx: Ctx, cfg: Config) async -> Topic? {
    let mem = CaraMemory.shared
    let name = Brain.segments.first(where: { $0.id == id })?.name ?? id
    func make(_ facts: String, plain: String? = nil) -> Topic { Topic(label: id, facts: facts, plain: plain, name: name) }
    let song = ctx.next ?? ctx.last
    switch id {
    case "next_intro":
        guard let n = ctx.next else { return nil }
        return make(songFacts(n, when: "The NEXT") + " Introduce it with real excitement and one playful quip about the title, the artist's name or the vibe.",
                    plain: "Up next, \(n.artist) with \(n.title).")
    case "last_verdict":
        guard let l = ctx.last else { return nil }
        return make(songFacts(l, when: "The song that JUST played") + " Give it a verdict on a ridiculous scale she invents on the spot (like 'nine out of ten rubber ducks') and explain it in one cheeky line.",
                    plain: "That was \(l.artist) with \(l.title).")
    case "trivia", "artist_story":
        for t in [ctx.next, ctx.last].compactMap({ $0 }) {
            let isNext = ctx.next?.uri == t.uri
            let when = isNext ? "The NEXT" : "The song that JUST played"
            guard let tr = await getTrivia(t), !mentionsDeath(tr.text) else { continue }
            let key = "wiki|" + t.artist + "|" + String(tr.text.prefix(60))
            let aboutArtist = id == "artist_story"
            if aboutArtist && tr.subject != t.artist {
                guard let bio = await wikiLookup("\(t.artist) musician band singer", must: [t.artist]), !mentionsDeath(bio) else { continue }
                return make("\(when) song is \"\(t.title)\" by \(t.artist). Real background on \(t.artist) (from Wikipedia): \"\"\"\(bio)\"\"\" Share ONE surprising, specific detail about the artist from that text, in your own words, like you just remembered it. Nothing that isn't in the text; skip anything sad, dark or about scandals.")
            }
            if !mem.isFresh(key, days: 2) { continue }
            mem.markUsed(key)
            let cleaned = tr.text.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            let sentences = cleaned.components(separatedBy: ". ").dropFirst().map { $0.hasSuffix(".") ? $0 : $0 + "." }
            let good = sentences.filter { $0.count > 40 && $0.count < 200 && !mentionsDeath($0) }
            return make("\(when) song is \"\(t.title)\" by \(t.artist). Real background on \(tr.subject) (from Wikipedia): \"\"\"\(tr.text)\"\"\" Share exactly ONE interesting, specific fact from that text that you haven't used before, in your own words. Never add anything that isn't in the text; skip anything sad, dark, or about scandals or lawsuits.",
                        plain: good.randomElement().map { "Fun fact about \(t.artist): " + $0 })
        }
        return nil
    case "time_machine":
        guard let t = song, let y = Int(t.year), y > 1900 else { return nil }
        let now = Calendar.current.component(.year, from: Date())
        let ago = now - y
        let when = ctx.next?.uri == t.uri ? "The NEXT" : "The song that JUST played"
        let age = ago <= 0 ? "it came out this year" : (ago == 1 ? "that's one year ago" : "that's \(ago) years ago")
        return make("\(when) song, \"\(t.title)\" by \(t.artist), came out in \(t.year) (\(age)). Riff on how long ago that feels and what the listener was probably up to back then, playful and general. Invent nothing about the artist.")
    case "your_stats":
        let lib = Library.shared
        let artists = lib.topArtists.prefix(3).map { $0.name }
        let tracks = lib.topTracks.prefix(3).map { "\"\($0.title)\" by \($0.artist)" }
        guard !artists.isEmpty || !tracks.isEmpty else { return nil }
        var f = "From the listener's own Spotify listening:"
        if !artists.isEmpty { f += " their most-played artists lately are \(artists.joined(separator: ", "))." }
        if let t = tracks.first { f += " A song they've had on heavy rotation lately: \(t)." }
        return make(f + " Tease them lovingly about it, like she's caught them red-handed. Pick ONE of these to focus on.")
    case "hot_take":
        guard let t = song else { return nil }
        return make("A playful hot take about the vibe of \"\(t.title)\" by \(t.artist): what weather it belongs to, what it would smell like, or what it's secretly about. It's an opinion, so invent nothing factual about the artist.")
    case "sing_along":
        guard let n = ctx.next else { return nil }
        return make("Dare the listener to sing along to the next song, \"\(n.title)\" by \(n.artist), at full volume. Don't quote any lyrics.")
    case "music_news":
        guard let h = await freshHeadline(musicFeeds, extra: gossipSkipRegex) else { return nil }
        return make("A music-industry headline (tell it in your own words, add no claims beyond it): " + h, plain: h + ".")
    case "local_news":
        guard let h = await freshHeadline(localFeeds(city: cfg.city)) else { return nil }
        return make("One headline from around \(cfg.city) (say what it says, in your own words, then react; add nothing): " + h, plain: h + ".")
    case "weather_now":
        guard let w = await getWeather(lat: cfg.lat, lon: cfg.lon) else { return nil }
        return make("The weather in \(cfg.city) right now: \(w.temp) degrees Fahrenheit, \(w.rain ? "and it's raining" : "no rain"). Turn it into a playful little forecast for the listener's mood or plans.",
                    plain: "It's \(w.temp) degrees out there\(w.rain ? " and wet" : "").")
    case "forecast":
        guard let w = await getForecast(lat: cfg.lat, lon: cfg.lon) else { return nil }
        return make("Today's forecast for \(cfg.city): a high of \(w.high) and a low of \(w.low) degrees Fahrenheit, with a \(w.rain) percent chance of rain. Deliver it with personality and one cheeky bit of advice.",
                    plain: "Today: a high of \(w.high), a low of \(w.low).")
    case "time_check":
        let f = DateFormatter()
        f.dateFormat = "EEEE h:mm a"
        let t = f.string(from: Date())
        return make("It's \(t). Riff on what this exact time of day is really for.", plain: "It's \(t).")
    case "day_vibe":
        let cal = Calendar.current
        let d = Date()
        let mf = DateFormatter()
        mf.dateFormat = "MM-dd"
        let wd = DateFormatter()
        wd.dateFormat = "EEEE"
        let month = cal.component(.month, from: d)
        let season: String
        switch month {
        case 12, 1, 2: season = "winter"
        case 3, 4, 5: season = "spring"
        case 6, 7, 8: season = "summer"
        default: season = "autumn"
        }
        var f = "It's \(wd.string(from: d)), in \(season)."
        if let hol = Brain.holidays[mf.string(from: d)] { f += " Today is \(hol)." }
        if month == 10 { f += " It's October, which means spooky season and pumpkin-spice everything." }
        if month == 11 && cal.component(.weekday, from: d) == 5 {
            let day = cal.component(.day, from: d)
            if day >= 22 && day <= 28 { f += " It's Thanksgiving in the US." }
        }
        return make(f + " Riff on the vibe of the day in one fresh, playful way.")
    case "hometown":
        if cfg.city.lowercased().hasPrefix("yakima") {
            let fact = mem.fresh("yakima", Brain.yakima)
            return make("A fact about \(cfg.city) (true, you can say it): \(fact) Give the town some playful love.", plain: fact)
        }
        return make("Give \(cfg.city) some playful love: what makes its people great, said generally and warmly. Invent no facts, places or names.")
    case "traffic_joke":
        return make("A totally fake, obviously silly 'travel report' about the listener's life (the queue for the kettle, a jam in the sock drawer, delays on the road to bed). Never mention real roads, accidents or delays.")
    case "weird_news":
        guard let h = await freshHeadline(worldFeeds) else { return nil }
        return make("A weird-but-true story from somewhere in the world (NOT from \(cfg.city)): " + h + " Tell it in your own words, then react.", plain: h + ".")
    case "science":
        guard let h = await freshHeadline(["https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", feed("scientists discover")]) else { return nil }
        return make("A science headline (say only what it says): " + h, plain: h + ".")
    case "space":
        guard let h = await freshHeadline([feed(#"NASA OR astronomers OR telescope OR "space station" OR planet"#)]) else { return nil }
        return make("A space headline (say only what it says): " + h, plain: h + ".")
    case "tech":
        guard let h = await freshHeadline([gtopic("TECHNOLOGY"), feed(#"gadget OR "new device" OR robot"#)]) else { return nil }
        return make("A gadgets-and-tech headline (say only what it says): " + h, plain: h + ".")
    case "animals":
        guard let h = await freshHeadline([feed(#"zoo OR "animal rescue" OR wildlife OR puppy OR kitten OR "baby animal""#)]) else { return nil }
        return make("A heart-warming animal story (say only what it says): " + h, plain: h + ".")
    case "food":
        guard let h = await freshHeadline([feed(#""food trend" OR snack OR "new menu" OR chef OR bakery"#)]) else { return nil }
        return make("A food headline (say only what it says): " + h, plain: h + ".")
    case "sports":
        guard let h = await freshHeadline([gtopic("SPORTS")]) else { return nil }
        return make("A sports headline (say only what it says, keep it light and fun): " + h, plain: h + ".")
    case "showbiz":
        guard let h = await freshHeadline(gossipFeeds, extra: gossipSkipRegex) else { return nil }
        return make("A showbiz headline (say ONLY what it says, add no rumours, tease affectionately, never mock anyone's looks or private life): " + h, plain: h + ".")
    case "screen":
        guard let h = await freshHeadline([feed(#"trailer OR "new series" OR "box office" OR premiere OR sequel"#)], extra: gossipSkipRegex) else { return nil }
        return make("A films-and-TV headline (say only what it says): " + h, plain: h + ".")
    case "on_this_day":
        let list = await onThisDay()
        guard let e = list.filter({ mem.isFresh($0, days: 300) }).randomElement() else { return nil }
        mem.markUsed(e)
        return make(e + " Share it in your own words and react.", plain: e)
    case "fun_fact":
        let f = mem.fresh("funFacts", Brain.funFacts)
        return make("A true fun fact (say it in your own words): " + f, plain: "Fun fact: " + f)
    case "word":
        let w = mem.fresh("words", Brain.words)
        return make("Word of the day: '\(w.w)', meaning \(w.m). Teach it, then use it in a silly example about the listener.",
                    plain: "Word of the day: \(w.w). It means \(w.m).")
    case "lore":
        return make("A quick first-person story from her Los Santos days, told with a punchline (use only these details, add reactions but no big new facts): " + mem.fresh("lore", Brain.lore))
    case "confession":
        return make("A silly confession about herself: " + mem.fresh("confessions", Brain.confessions) + ". Own it dramatically.")
    case "opinion":
        return make("Her strong, ridiculous opinion on this burning question: " + mem.fresh("opinions", Brain.opinions) + " Pick a side, defend it absurdly, and dare the listener to disagree.")
    case "fake_ad":
        return make("A short parody advert, read by Cara, for this totally made-up product: " + mem.fresh("fakeAds", Brain.fakeAds) + " Include a ridiculous catchphrase for it and a fake 'terms and conditions' line at top speed.")
    case "station_hype":
        return make("Hype the station, \(ctx.stationFull), itself in a fresh, absurd way: what it'd be if it were a person, a food or a weather system, or a ridiculous line about it, said dead straight as if it's always been the station's motto.")
    case "roast":
        return make("A playful roast. " + mem.fresh("roasts", Brain.roasts))
    case "compliment":
        return make("Give the listener a backhanded compliment that's really a tease, then a sincere one.")
    case "horoscope":
        let sign = Brain.signs.randomElement() ?? "Leo"
        return make("A completely made-up, obviously silly horoscope for \(sign), with a weirdly specific prediction about snacks, socks, songs or parking.")
    case "advice":
        return make("Terrible-but-harmless agony-aunt advice for the listener's dilemma: " + mem.fresh("dilemmas", Brain.dilemmas))
    case "pep_talk":
        return make("An over-the-top motivational speech about " + mem.fresh("pepTalks", Brain.pepTalks) + ", like it's the biggest moment of the listener's life.")
    case "hypothetical":
        return make("Picture this: " + mem.fresh("hypotheticals", Brain.hypotheticals) + ". Paint the scene in a few vivid, silly strokes.")
    case "would_you_rather":
        let q = mem.fresh("wyr", Brain.wouldYouRather)
        return make("Ask the listener: would you rather " + q + "? Then give her own answer, with a ridiculous reason.", plain: "Would you rather \(q)?")
    case "pop_quiz":
        let q = mem.fresh("quiz", Brain.quiz)
        let answer: String = q.a.prefix(1).uppercased() + String(q.a.dropFirst())
        return make("A pop quiz for the listener. Question: \(q.q) Answer: \(q.a). Ask it, give them a few seconds of fake suspense, then reveal the answer.",
                    plain: "Quick quiz: \(q.q) The answer? \(answer).")
    case "debate":
        return make("Start a silly debate: " + mem.fresh("opinions", Brain.opinions) + " Argue BOTH sides like two people, then declare yourself the winner.")
    case "challenge":
        return make("A car-safe challenge for the listener (voice only): " + mem.fresh("challenges", Brain.challenges))
    default:
        return nil
    }
}

private func available(_ id: String, _ ctx: Ctx) -> Bool {
    switch id {
    case "next_intro", "sing_along": return ctx.next != nil
    case "last_verdict": return ctx.last != nil
    case "trivia", "artist_story", "time_machine", "hot_take": return ctx.next != nil || ctx.last != nil
    default: return true
    }
}

/// Picks what this break is about: weighted, never one of her last few, and rarely the same family twice in a row.
@MainActor
func pickTopic(ctx: Ctx, cfg: Config) async -> Topic {
    let mem = CaraMemory.shared
    let recentSegs = Set(mem.last("segments", 10))
    let lastFamily = mem.last("segments", 1).first.flatMap { id in Brain.segments.first(where: { $0.id == id })?.family }
    var pool: [(String, Int)] = []
    for s in Brain.segments where available(s.id, ctx) && !recentSegs.contains(s.id) {
        let w = s.family == lastFamily ? max(1, s.weight / 3) : s.weight
        pool.append((s.id, w))
    }
    while !pool.isEmpty {
        let id = weightedPick(pool)
        if let t = await topicFor(id, ctx: ctx, cfg: cfg) { return t }
        pool.removeAll { $0.0 == id }
    }
    return await topicFor("fun_fact", ctx: ctx, cfg: cfg) ?? Topic(label: "fun_fact", facts: Brain.funFacts[0], name: "Fun fact")
}

func currentMood(_ cfg: Config) -> String {
    cfg.mood == "mixed" ? pick(["chill", "normal", "unhinged"]) : cfg.mood
}

private let moodLines: [String: String] = [
    "chill": "CHILL: laid-back, warm and smooth, with dry wit and fewer exclamation marks. Still playful, never sleepy.",
    "normal": "NORMAL: her usual bubbly, cheeky, quick self.",
    "unhinged": "UNHINGED: maximum playful chaos. Over-the-top drama, absurd tangents, gleeful mock outrage and silly voices described in words, but never mean.",
]

private let situations: [String: String] = [
    "silent": "The music has stopped and the floor is all hers. She launches straight into her segment with confidence (never mention the silence or the music stopping) and brings the next song in at the end.",
    "intro": "The next song has just started and she's talking over its opening. A quick, punchy drop-in (the song may kick in straight away, so never ramble), and she brings the song in at the end.",
    "talkover": "The current song is fading out under her voice. She rides the ending and rolls straight into the next song, no goodbyes or sign-offs.",
]

private func wordRange(style: String, chat: String) -> (Int, Int) {
    // over the start of a song she keeps it to a quick drop-in, so a song that kicks in straight away isn't buried
    if style == "intro" {
        switch chat {
        case "quick": return (8, 14)
        case "normal": return (10, 18)
        default: return (12, 22)
        }
    }
    let silent = style == "silent"
    switch chat {
    case "quick": return silent ? (20, 40) : (12, 28)
    case "normal": return silent ? (35, 60) : (20, 40)
    default: return silent ? (55, 95) : (30, 55)
    }
}

/// Words she may reuse freely (the song, the artist, the town, the station).
private func reusable(_ ctx: Ctx, _ cfg: Config) -> Set<String> {
    var s: Set<String> = ["non", "stop", "pop", "cara", "fm", "station"]
    for w in Repeats.words(ctx.station + " " + (ctx.switchedFrom ?? "")) { s.insert(w) }
    for t in [ctx.next, ctx.last].compactMap({ $0 }) {
        for w in Repeats.words(t.title + " " + t.artist + " " + t.album) where w.count > 2 { s.insert(w) }
    }
    for w in Repeats.words(cfg.city) { s.insert(w) }
    return s
}

@MainActor
private func memoryBlock(_ mem: CaraMemory, skip: Set<String>) -> String {
    let recent = mem.recent
    guard !recent.isEmpty else { return "- This is your first break today. Make it count." }
    var lines: [String] = ["- Your most recent breaks, newest first. Never reuse their openings, jokes, phrases, angles, facts or structure:"]
    for (i, b) in recent.suffix(12).reversed().enumerated() { lines.append("  \(i + 1). \"\(b)\"") }
    let openers = Array(Set(recent.suffix(30).map { Repeats.opener($0) }.filter { !$0.isEmpty })).prefix(30)
    if !openers.isEmpty { lines.append("- Never start with any of these: " + openers.map { "\"\($0)\"" }.joined(separator: ", ")) }
    let worn = Repeats.wornOut(recent, skip: skip)
    if !worn.isEmpty { lines.append("- Phrases you've worn out (don't use them): " + worn.map { "\"\($0)\"" }.joined(separator: ", ")) }
    return lines.joined(separator: "\n")
}

/// Allowed voice tags stay; anything else in square brackets goes.
private func cleanTags(_ t: String, allowed: Set<String>) -> (text: String, tags: [String]) {
    var used: [String] = []
    var out = ""
    var rest = Substring(t)
    while let open = rest.firstIndex(of: "[") {
        out += rest[..<open]
        guard let close = rest[open...].firstIndex(of: "]") else { out += rest[open...]; rest = ""; break }
        let tag = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces).lowercased()
        if allowed.contains(tag) {
            out += "[" + tag + "]"
            used.append(tag)
        }
        rest = rest[rest.index(after: close)...]
    }
    out += rest
    let tidied = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
    return (tidied, used)
}

/// Asks Gemini, checks the draft against her memory and rules, and rewrites up to twice.
@MainActor
private func freshDraft(_ prompt: String, cfg: Config, skip: Set<String>, allowedTags: Set<String>, log: (String) -> Void) async -> (text: String, tags: [String])? {
    let mem = CaraMemory.shared
    var feedback = ""
    var best: (text: String, tags: [String])? = nil
    for attempt in 0..<3 {
        let ask = feedback.isEmpty ? prompt : prompt + "\n\nYour previous draft can't be used: \(feedback) Write a completely new one."
        guard let raw = await gemini(ask, key: cfg.geminiKey, log: log) else { break }
        let c = cleanTags(tidy(raw), allowed: allowedTags)
        if c.text.isEmpty { continue }
        if let why = Repeats.problem(c.text, recent: mem.recent, skip: skip) {
            log("[rewrite \(attempt + 1): \(why)]")
            feedback = why
            if best == nil && !mentionsDeath(c.text) && Repeats.saysLabel(c.text) == nil { best = c }
            continue
        }
        return c
    }
    return best
}

/// Writes one break: what she talks about, in which style, how she opens and lands, how long, and in which mood.
@MainActor
func writeBreak(style: String, topic: Topic, ctx: Ctx, cfg: Config, mood: String, log: (String) -> Void) async -> String {
    let mem = CaraMemory.shared
    let expressive = cfg.elevenModel.hasPrefix("eleven_v4") || cfg.elevenModel.hasPrefix("eleven_v3")
    let format = Brain.formats.filter { !mem.last("formats", 8).contains($0.id) }.randomElement() ?? Brain.formats[0]
    let haveSong = ctx.next != nil || ctx.last != nil
    let openingChoices = Brain.openings.filter { o in
        if mem.last("openings", 8).contains(o.id) { return false }
        if o.needs == "song" { return haveSong }
        if o.needs == "last" { return ctx.last != nil }
        return true
    }
    let opening = openingChoices.randomElement() ?? Brain.openings[0]
    let ending = Brain.endings.filter { !mem.last("endings", 5).contains($0) }.randomElement() ?? Brain.endings[0]
    let tagChoices = Array(Brain.tags.filter { !mem.last("tags", 4).contains($0) }.shuffled().prefix(2))
    let range = wordRange(style: style, chat: cfg.chattiness)
    let skip = reusable(ctx, cfg)
    log("[style: \(format.id) · opening: \(opening.id) · \(range.0)-\(range.1) words]")
    let switchLine: String = ctx.switchedFrom.map {
        "\n- Fresh news: the listener just switched stations, from \"\(Station.full($0))\" to \"\(ctx.stationFull)\". Welcome them to the new one somewhere in this break, in one quick, playful line (new name, same Cara)."
    } ?? ""

    let tagLine = expressive
        ? "She may use up to two emotion tags, ONLY [\(tagChoices.joined(separator: "] or ["))], each placed mid-sentence right before the words it colours (never first, never on its own). Or none."
        : "Don't use any square-bracket tags."
    let prompt = """
    You are Cara, the DJ on \(ctx.stationFull), broadcasting to \(cfg.city).
    \(Brain.persona)
    \(Brain.bible(ctx))
    \(Brain.stationLine(ctx))

    THIS BREAK
    - What's happening: \(situations[style] ?? situations["talkover"] ?? "")\(switchLine)
    - Length: \(range.0) to \(range.1) words.
    - Talk about: \(topic.facts)
    - Delivery: \(format.how)
    - Mood: \(moodLines[mood] ?? moodLines["normal"] ?? "")
    - Opening: \(opening.how)
    - Landing: \(ending)
    - Voice: \(tagLine)
    - It's \(timeOfDayWord()) for the listener.

    NEVER REPEAT YOURSELF
    \(memoryBlock(mem, skip: skip))

    \(Brain.rules)

    Song that's just finishing: \(ctx.last?.describe ?? "(unknown)")
    Next song: \(ctx.next?.describe ?? "(unknown)")
    (She may name the next song if it looks like a real song. If it looks like an advert, a radio clip or is unknown, she doesn't mention it.)
    Write only the words Cara says.
    """
    if let d = await freshDraft(prompt, cfg: cfg, skip: skip, allowedTags: Set(Brain.tags), log: log) {
        mem.remember(text: d.text, segment: topic.label, format: format.id, opening: opening.id, ending: ending, tags: d.tags, popin: nil)
        return d.text
    }
    let t = templateBreak(style: style, topic: topic, ctx: ctx, cfg: cfg)
    mem.remember(text: t, segment: topic.label, format: nil, opening: nil, ending: nil, tags: [], popin: nil)
    return t
}

/// A quick drop-in a few seconds into a song.
@MainActor
func writePopIn(track: Track?, station: String = Station.fallback, cfg: Config, log: (String) -> Void) async -> String {
    let mem = CaraMemory.shared
    let title = track?.title ?? "this one"
    let artist = track?.artist ?? ""
    let name = artist.isEmpty ? "\"\(title)\"" : "\"\(title)\" by \(artist)"
    var fact = ""
    if let t = track, let tr = await getTrivia(t), !mentionsDeath(tr.text) {
        fact = "A real fact you may use (never invent others): " + String(tr.text.prefix(400))
    }
    let kinds = Brain.popinKinds.filter { k in
        if mem.last("popins", 4).contains(k.id) { return false }
        if k.id == "fact" { return !fact.isEmpty }
        if k.id == "callback" { return mem.lastBreak != nil }
        return true
    }
    let kind = kinds.randomElement() ?? Brain.popinKinds[0]
    let range: (Int, Int) = cfg.chattiness == "quick" ? (8, 16) : (cfg.chattiness == "normal" ? (10, 22) : (14, 30))
    let expressive = cfg.elevenModel.hasPrefix("eleven_v4") || cfg.elevenModel.hasPrefix("eleven_v3")
    let tag = Brain.tags.filter { !mem.last("tags", 4).contains($0) }.randomElement() ?? "excited"
    let ctx = Ctx(last: nil, next: track, station: station)
    let skip = reusable(ctx, cfg)
    let factLine: String = fact.isEmpty ? "" : "- " + fact
    let callbackLine: String = kind.id == "callback" ? "- Her last break was: \"" + (mem.lastBreak ?? "") + "\"" : ""
    let voiceLine: String = expressive ? "She may use one emotion tag, ONLY [" + tag + "], mid-sentence. Or none." : "No square-bracket tags."
    log("[pop-in style: \(kind.id)]")
    let prompt = """
    You are Cara, the DJ on \(ctx.stationFull), broadcasting to \(cfg.city).
    \(Brain.persona)

    The song \(name) started a few seconds ago, and she pops back in over it.
    - What to do: \(kind.how)
    - Length: \(range.0) to \(range.1) words.
    \(factLine)
    \(callbackLine)
    - Voice: \(voiceLine)
    - High energy, quick, no goodbye or sign-off.

    NEVER REPEAT YOURSELF
    \(memoryBlock(mem, skip: skip))

    \(Brain.rules)
    Write only the words Cara says.
    """
    if let d = await freshDraft(prompt, cfg: cfg, skip: skip, allowedTags: Set(Brain.tags), log: log) {
        mem.remember(text: d.text, segment: nil, format: nil, opening: nil, ending: nil, tags: d.tags, popin: kind.id)
        return d.text
    }
    let line = mem.fresh("popinTemplates", [
        "That's \(name). Turn it up, I'll wait.",
        "\(name), and your taste is getting suspiciously good.",
        "Still with me? Course you are. This is \(name).",
        "\(name). Hum along, nobody's judging. I am, a bit.",
        "Right in the middle of \(name), and I've got no notes.",
        "Quick one: \(name). Carry on, superstar.",
    ])
    mem.remember(text: line, segment: nil, format: nil, opening: nil, ending: nil, tags: [], popin: "template")
    return line
}

func timeOfDayWord() -> String {
    let h = Calendar.current.component(.hour, from: Date())
    return h < 5 ? "late night" : h < 12 ? "morning" : h < 17 ? "afternoon" : "evening"
}

/// When there's no Gemini key: simple lines, still varied, still never the same opening twice in a row.
@MainActor
func templateBreak(style: String, topic: Topic, ctx: Ctx, cfg: Config) -> String {
    let mem = CaraMemory.shared
    let openers: [String] = [
        "Cara here, keeping you company.", "\(ctx.stationFull), Cara on the mic.", "Hello, \(cfg.city)!",
        "Cara again. Did you miss me?", "This is Cara, live-ish and lovely.", "Guess who's back.",
        "Your favourite voice, reporting for duty.", "Cara checking in.", "Here's Cara, with absolutely no notes.",
        "It's me, the voice in your speakers.", "\(ctx.station), and I'm still here.", "Cara, back by popular demand.",
    ]
    let closers: [String] = [
        "Back to the music.", "Here's the next one.", "Turn it up for this.", "Stay right there.",
        "Don't go anywhere.", "More pop, coming right up.", "You're in good hands.", "Off we go.",
        "Right, on with the show.", "This next one's a goodie.",
    ]
    var middle = topic.plain ?? ""
    if middle.isEmpty {
        if let n = ctx.next { middle = "Up next, \(n.artist), with \(n.title)." } else { middle = "More of the good stuff, coming up." }
    }
    return mem.fresh("tplOpen", openers) + " " + middle + " " + mem.fresh("tplClose", closers)
}

// MARK: - Cara and Scratch together
// Some breaks are a back-and-forth with her co-host, Scratch (an original character, see CoHost.swift).
extension Brain {
    struct DuoSegment {
        let id: String
        let name: String
        /// One of Cara's own segments to get the facts from (nil when the angle needs none).
        let base: String?
        let angle: String
        let weight: Int
    }

    static let duoSegments: [DuoSegment] = [
        DuoSegment(id: "drama_desk", name: "Drama desk", base: "showbiz", angle: "They react like two friends spilling the tea: one is scandalised, the other completely unbothered, and they bicker about who's right. Say only what the headline says; add no rumours and never mock anyone's looks or private life.", weight: 4),
        DuoSegment(id: "music_news", name: "Music news, two takes", base: "music_news", angle: "Each gives a quick hot take: Scratch like a hip-hop purist, Cara like a pop superfan. Say only what the headline says.", weight: 3),
        DuoSegment(id: "pop_vs_hiphop", name: "Pop vs hip-hop", base: "next_intro", angle: "They argue about the next song: Scratch rates it on his hip-hop scale, Cara defends it, and they find one thing they agree on before it starts.", weight: 3),
        DuoSegment(id: "two_judges", name: "Two-judge verdict", base: "last_verdict", angle: "They judge the song that just played like two talent-show judges: each scores it on a ridiculous scale of their own invention, one harsh and one gushing, and they argue about who's right.", weight: 2),
        DuoSegment(id: "tag_team", name: "Tag-team intro", base: "next_intro", angle: "They hype the next song together like a tag team, finishing each other's sentences, and count it in.", weight: 3),
        DuoSegment(id: "roast_battle", name: "Roast battle", base: nil, angle: "A quick, affectionate roast battle between the two DJs about each other's music taste, their old Los Santos stations and their on-air habits (never looks, bodies or identity): two or three jabs each, then a truce.", weight: 3),
        DuoSegment(id: "story_swap", name: "Los Santos story swap", base: nil, angle: "Scratch tells his story, Cara tries to top it with hers, and they argue about whose was worse.", weight: 3),
        DuoSegment(id: "debate", name: "Silly debate", base: nil, angle: "Cara takes one side and Scratch the other; each makes an absurd case, and they hand the deciding vote to the listener.", weight: 3),
        DuoSegment(id: "would_you_rather", name: "Would you rather", base: nil, angle: "They put it to each other and both answer with ridiculous reasons.", weight: 2),
        DuoSegment(id: "quiz", name: "Quiz each other", base: nil, angle: "One quizzes the other with fake suspense; whoever loses owes a silly forfeit (voice only).", weight: 2),
        DuoSegment(id: "advice", name: "Advice line", base: nil, angle: "Cara gives terrible-but-harmless agony-aunt advice, Scratch gives even worse 'uncle' advice, and they argue about whose is better.", weight: 2),
        DuoSegment(id: "fake_ad", name: "Fake advert double act", base: nil, angle: "They read a parody advert for it together, tripping over each other's lines, with a fake 'terms and conditions' at top speed.", weight: 2),
        DuoSegment(id: "listener_court", name: "Listener court", base: "your_stats", angle: "The listener at home is on trial for their listening habits (these are the listener's stats, never Scratch's or Cara's): Cara prosecutes, Scratch defends them (badly), both talking about \"our listener\" or to \"you at home\", and they reach a ridiculous verdict.", weight: 2),
        DuoSegment(id: "around_town", name: "Around town", base: "local_news", angle: "They react with some hometown pride, and Scratch compares it to how things were in Los Santos. Say only what the headline says.", weight: 2),
        DuoSegment(id: "weather", name: "Weather fight", base: "forecast", angle: "They argue about what the weather means for the listener's plans; Scratch has strong opinions about the right car-window position.", weight: 1),
        DuoSegment(id: "station_name", name: "The station's name", base: nil, angle: "The listener picked this (it's their playlist or album, not either DJ's): the DJs tease the listener at home about the name and argue with each other about what it says about them.", weight: 1),
        DuoSegment(id: "peace_talk", name: "Scratch's peace talk", base: nil, angle: "Scratch delivers a mock-serious, big-brother peace-and-unity speech about a petty studio beef between him and Cara (the aux cord, the thermostat, the last snack), Cara keeps stirring it, and they squash it by the end.", weight: 2),
        DuoSegment(id: "hustle_talk", name: "Hustle talk", base: nil, angle: "Scratch hands out big-brother money and hustle advice for the listener (saving up, side gigs, getting the bag the legit way), each tip with a punchline, and Cara counters with gloriously terrible money advice of her own.", weight: 2),
        DuoSegment(id: "food_fight", name: "Food fight", base: nil, angle: "They argue about the best late-night food: Scratch is a taco-truck loyalist, Cara defends something hopelessly British, and they settle it with a bet. Food in general only, no real restaurant names.", weight: 2),
        DuoSegment(id: "first_play", name: "Heat nobody else has", base: "next_intro", angle: "Scratch hypes the next song like this station dug it up before anyone else on the planet, Cara reminds him the listener picked it, and he takes the credit anyway.", weight: 2),
        DuoSegment(id: "shade_review", name: "Scratch's shade review", base: "last_verdict", angle: "Scratch reviews the song that just played with smooth, surgical shade (a backhanded compliment, a pause you can hear, one devastating word), Cara defends it, and he admits the one thing he secretly liked.", weight: 2),
        DuoSegment(id: "west_coast", name: "West Coast vs London", base: nil, angle: "Scratch makes his case that everything is better on the West Coast (the weather, the food, the cars, the sunsets, the music), Cara defends Britain, rain and all, and they hand the deciding vote to the listener.", weight: 2),
    ]

    static let duoEndings: [String] = [
        "End with Scratch bringing the next song in by name, and Cara getting the last word.",
        "End with Cara bringing the next song in by name while Scratch grumbles he'd have spun it louder back on The Heat.",
        "End with them agreeing on exactly one thing, then the song.",
        "End mid-argument, with one of them cutting to the song to win it.",
        "End with a quick bet between them about the next song.",
        "End with a callback to how the conversation opened.",
        "End with one of them giving the listener a silly, car-safe job for the next song.",
        "End with a fake truce that lasts exactly one line.",
        "End with Scratch getting one last bit of shade in as the song starts, and Cara letting him have it, just this once.",
    ]
}

private let duoSituations: [String: String] = [
    "silent": "The music has stopped and the studio is theirs. They dive straight in (never mention the silence or the music stopping) and bring the next song in at the end.",
    "intro": "The next song has just started and they're talking over its opening. A quick exchange (the song may kick in straight away, so never ramble), then they let it play.",
    "talkover": "The current song is fading out under them. They wrap up as it ends and roll straight into the next song, no goodbyes.",
]

/// What Cara and Scratch talk about together: weighted, never one of their last few.
@MainActor
func pickDuoTopic(ctx: Ctx, cfg: Config) async -> Topic {
    let recent = Set(CaraMemory.shared.last("segments", 8))
    var pool: [(String, Int)] = Brain.duoSegments.filter { !recent.contains("duo_" + $0.id) }.map { ($0.id, $0.weight) }
    if ctx.station == Station.fallback { pool.removeAll { $0.0 == "station_name" } }
    while !pool.isEmpty {
        let id = weightedPick(pool)
        if let s = Brain.duoSegments.first(where: { $0.id == id }), let t = await duoTopicFor(s, ctx: ctx, cfg: cfg) { return t }
        pool.removeAll { $0.0 == id }
    }
    return Topic(label: "duo_roast_battle", facts: Brain.duoSegments[5].angle, name: "Roast battle")
}

@MainActor
private func duoTopicFor(_ s: Brain.DuoSegment, ctx: Ctx, cfg: Config) async -> Topic? {
    let mem = CaraMemory.shared
    var facts = ""
    var plain: String? = nil
    if let base = s.base {
        guard let t = await topicFor(base, ctx: ctx, cfg: cfg) else { return nil }
        facts = t.facts
        plain = t.plain
    } else {
        switch s.id {
        case "story_swap":
            facts = "\(CoHost.short)'s story from his Los Santos days (use only these details): " + mem.fresh("coLore", CoHost.lore)
                + " Cara's story to top it (use only these details): " + mem.fresh("lore", Brain.lore)
        case "debate":
            facts = "The burning question: " + mem.fresh("opinions", Brain.opinions)
        case "would_you_rather":
            facts = "Would you rather " + mem.fresh("wyr", Brain.wouldYouRather) + "?"
        case "quiz":
            let q = mem.fresh("quiz", Brain.quiz)
            facts = "Question: \(q.q) Answer: \(q.a)."
        case "advice":
            facts = "A listener's dilemma: " + mem.fresh("dilemmas", Brain.dilemmas)
        case "fake_ad":
            facts = "A totally made-up product: " + mem.fresh("fakeAds", Brain.fakeAds)
        case "station_name":
            facts = "The station is named after \(ctx.stationNote.isEmpty ? "\"\(ctx.station)\"" : ctx.stationNote), so on air it's \"\(ctx.stationFull)\"."
        default:
            break
        }
    }
    return Topic(label: "duo_" + s.id, facts: facts.isEmpty ? s.angle : facts + " " + s.angle, plain: plain, name: s.name)
}

/// Reads "CARA: ..." / "SCRATCH: ..." lines (anything else joins the line before it).
func parseDuo(_ raw: String) -> [DuoLine] {
    var out: [DuoLine] = []
    // "MC SCRATCH:" counts as "SCRATCH:", and a speaker label in the middle of a line starts a new line
    // (tidying squashes a blank line between turns into a space)
    var text = raw
    let full = CoHost.name.uppercased()
    if full != CoHost.label {
        text = text.replacingOccurrences(of: "\\**" + NSRegularExpression.escapedPattern(for: full) + "\\**\\s*:",
                                         with: CoHost.label + ":", options: .regularExpression)
    }
    text = text.replacingOccurrences(of: "\\s+(?=\\**(?:CARA|" + NSRegularExpression.escapedPattern(for: CoHost.label) + ")\\**\\s*:)",
                                     with: "\n", options: .regularExpression)
    for piece in text.components(separatedBy: .newlines) {
        var l = piece.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
        while l.hasPrefix("-") || l.hasPrefix("•") { l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if l.isEmpty { continue }
        if let colon = l.firstIndex(of: ":") {
            let who = l[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let text = l[l.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if who == "CARA" || who == CoHost.label || who == CoHost.name.uppercased() {
                if !text.isEmpty { out.append(DuoLine(who: who == "CARA" ? "CARA" : CoHost.label, text: text)) }
                continue
            }
        }
        if let last = out.popLast() { out.append(DuoLine(who: last.who, text: last.text + " " + l)) }
    }
    return out
}

/// Writes one Cara-and-Scratch exchange, checked against their memory like her solo breaks. Empty if it couldn't.
@MainActor
func writeDuo(style: String, topic: Topic, ctx: Ctx, cfg: Config, mood: String, log: (String) -> Void) async -> [DuoLine] {
    let mem = CaraMemory.shared
    let expressive = cfg.elevenModel.hasPrefix("eleven_v4") || cfg.elevenModel.hasPrefix("eleven_v3")
    let silent = style == "silent"
    let shape: (lo: Int, hi: Int, words: Int)
    switch cfg.chattiness {
    case "quick": shape = silent ? (3, 4, 50) : (style == "intro" ? (2, 2, 18) : (2, 2, 28))
    case "normal": shape = silent ? (4, 6, 80) : (style == "intro" ? (2, 2, 22) : (2, 3, 38))
    default: shape = silent ? (5, 8, 110) : (style == "intro" ? (2, 3, 26) : (2, 4, 48))
    }
    let first = Bool.random() ? "Cara" : CoHost.short
    let ending = Brain.duoEndings.filter { !mem.last("endings", 5).contains($0) }.randomElement() ?? Brain.duoEndings[0]
    let tagChoices = Array(Brain.tags.filter { !mem.last("tags", 4).contains($0) }.shuffled().prefix(3))
    var skip = reusable(ctx, cfg)
    let songWords = Set(Repeats.words([ctx.last?.describe, ctx.next?.describe].compactMap { $0 }.joined(separator: " ")))
    for w in ["scratch", "mc", "london", "vinyl"] { skip.insert(w) }
    let coMove = mem.fresh("coMoves", CoHost.moves)
    log("[duo: \(shape.lo)-\(shape.hi) lines, \(first) first]")
    let tagLine = expressive
        ? "Each line may use one emotion tag, ONLY [\(tagChoices.joined(separator: "] or ["))], placed mid-sentence right before the words it colours (never first). Most lines have none."
        : "Don't use any square-bracket tags."
    let switchLine: String = ctx.switchedFrom.map {
        "\n- Fresh news: the listener just switched stations, from \"\(Station.full($0))\" to \"\(ctx.stationFull)\". One of them welcomes the listener to the new one in a quick, playful line."
    } ?? ""
    let prompt = """
    You write a short on-air exchange between the two DJs of \(ctx.stationFull), broadcasting to \(cfg.city).
    CARA: \(Brain.persona)
    \(Brain.bible(ctx))
    \(CoHost.label): \(CoHost.persona)
    \(CoHost.language(cfg))
    \(CoHost.bible)
    \(CoHost.identity)
    \(Brain.stationLine(ctx))
    \(CoHost.whoIsWho)

    THIS BREAK
    - What's happening: \(duoSituations[style] ?? duoSituations["talkover"] ?? "")\(switchLine)
    - Talk about: \(topic.facts)
    - \(CoHost.short)'s move this time (work it in naturally): \(coMove)
    - Shape: a quick back-and-forth between two DJs and old friends who've done a thousand shows together: teasing, interruptions, callbacks, each firing back at the other. Every line is short (3 to 22 words) and sounds spoken, not written.
    - Length: \(shape.lo) to \(shape.hi) lines and \(shape.words) words at most in total. \(first) speaks first and they take turns.
    - Mood: \(moodLines[mood] ?? moodLines["normal"] ?? "")
    - Landing: \(ending)
    - Voice: \(tagLine)
    - It's \(timeOfDayWord()) for the listener.

    NEVER REPEAT YOURSELVES
    \(memoryBlock(mem, skip: skip))

    \(Brain.rules)
    - Scratch is the one exception to the no-invented-characters rule: he's her co-host, in the studio with her. Nobody else joins them.
    - Scratch follows every rule too. Neither of them is a real radio host: never mention, name or imitate real DJs or presenters, and never claim to know celebrities personally.

    Song that's just finishing: \(ctx.last?.describe ?? "(unknown)")
    Next song: \(ctx.next?.describe ?? "(unknown)")
    (They may name the next song if it looks like a real song. If it looks like an advert, a radio clip or is unknown, they don't mention it.)
    Write ONLY the dialogue: one line per turn, each starting with CARA: or \(CoHost.label):
    """
    var feedback = ""
    var best: [DuoLine]? = nil
    for attempt in 0..<3 {
        let ask = feedback.isEmpty ? prompt : prompt + "\n\nYour previous draft can't be used: \(feedback) Write a completely new one."
        guard let raw = await gemini(ask, key: cfg.geminiKey, log: log) else { break }
        // a masked curse ("sh*t") gets read out as nonsense, so he says it in full or not at all
        if raw.range(of: #"[A-Za-z]\*+[A-Za-z]|\b[A-Za-z]\*{2,}"#, options: .regularExpression) != nil {
            feedback = "It hid a word behind asterisks. Write every word out in full, or pick a different word."
            log("[rewrite \(attempt + 1): masked word]")
            continue
        }
        var lines: [DuoLine] = []
        var used: [String] = []
        for l in parseDuo(raw) {
            let c = cleanTags(tidy(l.text), allowed: Set(Brain.tags))
            if !c.text.isEmpty {
                lines.append(DuoLine(who: l.who, text: c.text))
                used += c.tags
            }
        }
        let joined = lines.map { $0.text }.joined(separator: " ")
        let said = Set(Repeats.words(joined))
        if said.contains("grandpa") || said.contains("gramps") {
            feedback = "Cara gave him an old-man nickname. She only ever calls him Scratch."
            log("[rewrite \(attempt + 1): old-man nickname]")
            continue
        }
        if said.contains("alex") && !songWords.contains("alex") {
            feedback = "It called him Alex. His name is MC Scratch, Scratch for short."
            log("[rewrite \(attempt + 1): wrong name]")
            continue
        }
        if lines.contains(where: { !$0.isCoHost && !CoHost.swears(in: $0.text).isEmpty }) {
            feedback = "Cara swore. Only \(CoHost.short) curses; Cara keeps it clean."
            log("[rewrite \(attempt + 1): Cara swore]")
            continue
        }
        if !cfg.coHostSwears && !CoHost.swears(in: joined).isEmpty {
            feedback = "Keep it clean this time: no swearing from either of them."
            log("[rewrite \(attempt + 1): swearing]")
            continue
        }
        if CoHost.tooFar(joined) {
            feedback = "\(CoHost.short) went too far. He can curse where it lands, but keep it classy: never \"bitch\" or \"motherfucker\"."
            log("[rewrite \(attempt + 1): too crude]")
            continue
        }
        if lines.count < 2 || !lines.contains(where: { $0.isCoHost }) || !lines.contains(where: { !$0.isCoHost }) {
            feedback = "It has to be a conversation: at least two lines, with both CARA: and \(CoHost.label): speaking."
            log("[rewrite \(attempt + 1): not a conversation]")
            continue
        }
        if let why = Repeats.problem(joined, recent: mem.recent, skip: skip) {
            log("[rewrite \(attempt + 1): \(why)]")
            feedback = why
            if best == nil && !mentionsDeath(joined) && Repeats.saysLabel(joined) == nil { best = lines }
            continue
        }
        mem.remember(text: joined, segment: topic.label, format: nil, opening: nil, ending: ending, tags: used, popin: nil)
        return lines
    }
    if let b = best {
        mem.remember(text: b.map { $0.text }.joined(separator: " "), segment: topic.label, format: nil, opening: nil, ending: ending, tags: [], popin: nil)
        return b
    }
    return []
}
