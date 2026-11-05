// The 50 Gremlets. Each is a one-of-a-kind design assembled from the part library.
// Families: animal, insect, dragon, dino, mythic.

import Foundation

/// Frog-style eye bumps on top of the head.
let eyeBumps: Draw = { cv, c in
    for x in [Double(c.lx) + 0.5, Double(c.rxp) + 0.5] { cv.ellipse(x, Double(c.eyeY) + 0.2, 2.8, 2.6, c.R) }
}

/// Jumping-spider secondary eyes.
let spiderSideEyes: Draw = { cv, c in
    for (x, y) in [(c.lx - 2, c.eyeY - 2), (c.rxp + 2, c.eyeY - 2), (c.lx - 3, c.eyeY), (c.rxp + 3, c.eyeY)] {
        cv.plot(x, y, 0xFFFFFF)
    }
}

let roster: [Species] = [
    // ---------------------------------------------------------------- Braydon's favourites
    species("flurrie", "Flurrie", "frost", "animal", main: 0xF4F8FF, "A snowball bunny with icicle ear-tips. Leaves a little frost wherever it hops.") {
        $0.rx = 8; $0.ry = 7.6; $0.eye = 0x1F2B4D; $0.cheek = 0xA9C9FF
        $0.back = [longEars(0xF59AA8, tip: 0xA8DFFF)]
        $0.special = "snow"; $0.walkSpeed = 75; $0.jumpPower = 1.25
    },
    species("kindlet", "Kindlet", "ember", "mythic", main: 0xF27A4B, "A melting-candle sprite whose flame flares when it's happy and dims to an ember when it naps.") {
        $0.body = .egg; $0.rx = 8; $0.ry = 7.5; $0.belly = 0xFFD6A5; $0.eye = 0x5A2416; $0.cheek = 0xFF8FA0
        $0.surface = [waxDrips(0xFFE3BC)]
        $0.top = [flame()]
        $0.special = "fire"; $0.walkSpeed = 70; $0.sleepiness = 0.8
    },
    species("dandelet", "Dandelet", "bloom", "animal", main: 0xF6D776, "A dandelion lion cub with a petal mane. Its puff tail scatters seeds when it bounces.") {
        $0.rx = 7; $0.ry = 6.8; $0.belly = 0xFFF3C4; $0.eye = 0x3D2A0E; $0.cheek = 0xFF9C7A
        $0.back = [petalMane(0xFFB830), seedPuffTail(0x6E9E4A, 0xFAFAF2)]
        $0.special = "petals"; $0.walkSpeed = 75; $0.jumpPower = 1.05; $0.sleepiness = 0.8
    },

    // ---------------------------------------------------------------- Animals
    species("mossfawn", "Mossfawn", "grove", "animal", main: 0xC99A6B, "A forest fawn whose antlers sprout tiny red mushrooms after it rains.") {
        $0.body = .egg; $0.rx = 7.5; $0.ry = 7.2; $0.belly = 0xF2DFC2; $0.eye = 0x3A2418; $0.mouthDY = 4
        $0.back = [antlers(0x8A6A4A, mushroom: 0xE0574F), fawnEars(0xF2C9B0), puffTail(0xFFF6E6)]
        $0.muzzle = snout(0xF2DFC2)
        $0.feet = .hooves(0x5A4030); $0.special = "leaves"; $0.walkSpeed = 80; $0.jumpPower = 1.2
    },
    species("pomble", "Pomble", "trickster", "animal", main: 0x8A6A4F, "A pot-bellied tanuki who keeps a leaf on its head for luck and drums its tummy when happy.") {
        $0.body = .pear; $0.rx = 8; $0.ry = 7.6; $0.belly = 0xE8D5B5; $0.eye = 0x1E140E; $0.limb = 0x5A4535; $0.mouthDY = 4
        $0.eyeStyle = .light
        $0.back = [roundEars(0x3D2B22, size: 0.9, color: 0x5A4535), bushyTail(0x8A6A4F, ring: 0x3D2B22)]
        $0.surface = [eyeMask(0x3D2B22)]
        $0.muzzle = snout(0xE8D5B5, w: 0.32)
        $0.special = "leaves"; $0.walkSpeed = 55
    },
    species("capyzen", "Capyzen", "onsen", "animal", main: 0xB07A4F, "A hot-spring capybara so calm that birds land on it. Nothing ruffles it.") {
        $0.body = .egg; $0.rx = 9; $0.ry = 7; $0.eye = 0x2A1A10; $0.mouthDY = 4
        $0.back = [roundEars(0x7A5030, size: 0.7, spread: 0.55)]
        $0.belly = 0xD9AE84
        $0.muzzle = snout(0x8A5A38, nose: 0x3A2214, w: 0.42)
        $0.special = "steam"; $0.walkSpeed = 40; $0.sleepiness = 1.6; $0.jumpPower = 0.8
    },
    species("seedcheek", "Seedcheek", "harvest", "animal", main: 0xBDB6C8, "A dwarf hamster whose cheeks are always stuffed with snacks it's saving for later.") {
        $0.rx = 7.5; $0.ry = 7; $0.belly = 0xFFF8F0; $0.eye = 0x2A1A10; $0.mouthDY = 4; $0.teeth = true
        $0.back = [roundEars(0xF7A6B4, size: 0.95)]
        $0.surface = [cheekPouches(0xD2CCDB)]
        $0.muzzle = snout(0xFFF8F0, nose: 0xE07A8A, w: 0.25)
        $0.special = "seeds"; $0.walkSpeed = 80
    },
    species("rustle", "Rustle", "autumn", "animal", main: 0xC8552B, "A red panda with a striped autumn tail. Stands up tall to look bigger when surprised.") {
        $0.rx = 7.6; $0.ry = 7.2; $0.belly = 0x5A3226; $0.limb = 0x4A2A22; $0.eye = 0x2A1410; $0.mouthDY = 4
        $0.back = [catEars(0xFFF4E8, size: 0.9), bushyTail(0xC8552B, ring: 0xF2C9A0, big: 1.1)]
        $0.surface = [browDots(0xFFF4E8)]
        $0.muzzle = snout(0xFFF4E8, w: 0.36)
        $0.special = "leaves"; $0.walkSpeed = 70
    },
    species("nimbuss", "Nimbuss", "sky", "animal", main: 0xEEF2FB, "A kitten made of cloud fluff. It drizzles a little when it's sad and floats when it's happy.") {
        $0.body = .cloud; $0.rx = 9; $0.ry = 7; $0.eye = 0x2B3157; $0.cheek = 0xB9C8FF
        $0.back = [catEars(0xC9D6F5), curlTail()]
        $0.flies = true; $0.special = "rain"; $0.jumpPower = 1.1
    },
    species("lilypip", "Lilypip", "pond", "animal", main: 0x7BC96F, "A round pond frog that hops much higher than anyone expects.") {
        $0.rx = 9; $0.ry = 6.5; $0.belly = 0xF4F2B0; $0.eye = 0x1A2A14; $0.faceV = -0.62; $0.eyeGap = 0.48; $0.mouthDY = 4
        $0.surface = [eyeBumps]
        $0.feet = .webbed(0x5FA855); $0.special = "bubbles"; $0.jumpPower = 1.4
    },
    species("swirlby", "Swirlby", "dew", "animal", main: 0xD3CFA6, "A snail with a perfectly round swirl shell. It's never late, just taking the scenic route.") {
        $0.rx = 5.4; $0.ry = 5.0; $0.eye = 0x2A2A1A; $0.noArms = true
        $0.back = [swirlShell(0xC98A5A, 0x8A4A2A)]
        $0.top = [eyeStalks(0xD3CFA6)]
        $0.feet = .slime(0xC8C49A); $0.special = "bubbles"; $0.walkSpeed = 22; $0.jumpPower = 0.6
    },
    species("duskwing", "Duskwing", "night", "animal", main: 0xB5743A, "A golden flying fox that sleeps all day and flutters out at dusk.") {
        $0.rx = 7; $0.ry = 6.8; $0.belly = 0xF0C878; $0.eye = 0x2A140A; $0.fangs = true
        $0.back = [batWings(0x6A4030, 0x3A2018), batEars(0xE8A890)]
        $0.flies = true; $0.special = "sparkle"; $0.sleepiness = 1.4
    },
    species("tidepaw", "Tidepaw", "river", "animal", main: 0x8C5E3C, "A river otter that floats on its back and holds paws with friends so nobody drifts away.") {
        $0.body = .pear; $0.rx = 7.5; $0.ry = 7.4; $0.belly = 0xF2DCC0; $0.eye = 0x1E120A; $0.mouthDY = 4
        $0.back = [roundEars(0x5E3E28, size: 0.6), lizardTail(0x8C5E3C, thick: 1.1, len: 0.9)]
        $0.muzzle = snout(0xF2DCC0)
        $0.top = [whiskers(0xFFFFFF)]
        $0.special = "bubbles"; $0.walkSpeed = 70
    },
    species("gumleaf", "Gumleaf", "eucalyptus", "animal", main: 0xB7B2AC, "A very fluffy koala who insists on being called Your Fluffiness.") {
        $0.rx = 8; $0.ry = 7.2; $0.belly = 0xF6F2EC; $0.eye = 0x1E1E24; $0.mouthDY = 5; $0.fluffy = true
        $0.back = [roundEars(0xF6F2EC, size: 1.45, spread: 0.75)]
        $0.muzzle = koalaNose()
        $0.special = "petals"; $0.walkSpeed = 45; $0.sleepiness = 1.3
    },
    species("dozel", "Dozel", "canopy", "animal", main: 0x9AA584, "A mossy sloth so slow that tiny plants grow in its fur.") {
        $0.body = .egg; $0.rx = 7.5; $0.ry = 7.5; $0.eye = 0x2A1E14; $0.limb = 0x8A7458; $0.restEyes = .sleepy; $0.eyeStyle = .light
        $0.surface = [facePatch(0xEFE2C8, w: 0.8, h: 0.6), eyeMask(0x6A5038)]
        $0.special = "petals"; $0.walkSpeed = 22; $0.sleepiness = 2.4; $0.jumpPower = 0.7
    },
    species("puffling", "Puffling", "sea", "animal", main: 0x2B2B3A, "A puffin chick with a beak too big for its face and a lot of confidence.") {
        $0.body = .egg; $0.rx = 7; $0.ry = 7.2; $0.belly = 0xF4F4F6; $0.eye = 0x1A1A24; $0.beak = true; $0.mouthDY = 5
        $0.back = [birdWings(0x2B2B3A, 0x4A4A5A)]
        $0.surface = [facePatch(0xF4F4F6, w: 0.75, h: 0.5)]
        $0.muzzle = beak(0xF26B3A, .puffin)
        $0.feet = .webbed(0xF28A3A); $0.flies = true; $0.special = "bubbles"
    },
    species("alpocco", "Alpocco", "highland", "animal", main: 0xF2E6D0, "A fluffy alpaca with a cloud of a hairdo. Hums when it's content.") {
        $0.rx = 7.5; $0.ry = 7.5; $0.eye = 0x2A1E14; $0.mouthDY = 4; $0.fluffy = true
        $0.back = [catEars(0xF2C9B0, size: 1.1, spread: 0.45)]
        $0.muzzle = snout(0xFFF6E8, nose: 0x6A4A3A)
        $0.top = [tuft()]
        $0.special = "notes"; $0.walkSpeed = 55
    },

    // ---------------------------------------------------------------- Insects & bugs
    species("silkwing", "Silkwing", "silk", "insect", main: 0x4A3B6B, "A fuzzy butterfly with stained-glass wings that glitter in the light.") {
        $0.rx = 6; $0.ry = 6.4; $0.eye = 0x1A1430; $0.cheek = 0xFF9EC4; $0.fluffy = true; $0.eyeStyle = .light
        $0.back = [butterflyWings(0xFF9EC4, 0x7FD3FF)]
        $0.top = [antennae(.ball, 0x4A3B6B, tip: 0xFFD54A)]
        $0.flies = true; $0.special = "sparkle"; $0.jumpPower = 1.2
    },
    species("zipwing", "Zipwing", "breeze", "insect", main: 0x3CC6B8, "A dragonfly with huge shiny eyes. Zips everywhere, stops for nothing.") {
        $0.rx = 6; $0.ry = 6; $0.eye = 0x0F3A3A; $0.eyeStyle = .bug(0x7DF0FF)
        $0.back = [dragonflyWings(0xE8FBFF), segmentTail(0x3CC6B8, band: 0x1F6F78)]
        $0.feet = .insect; $0.flies = true; $0.special = "sparkle"; $0.walkSpeed = 90
    },
    species("bumbuzz", "Bumbuzz", "pollen", "insect", main: 0xFFC93C, "A round, fuzzy bumblebee whose wings are far too small. It flies anyway.") {
        $0.rx = 7.2; $0.ry = 7; $0.eye = 0x2A1A0A; $0.fluffy = true
        $0.back = [beeWings(), stinger(0x3A2A1A)]
        $0.surface = [stripes(0x3A2A1A, count: 2, start: -0.8, gap: 1.22, thick: 1.8)]
        $0.top = [antennae(.ball, 0x3A2A1A)]
        $0.flies = true; $0.special = "pollen"; $0.walkSpeed = 50
    },
    species("spotsy", "Spotsy", "luck", "insect", main: 0xE8433A, "A shiny ladybug. Counting its spots is said to bring good luck.") {
        $0.body = .bugHead; $0.rx = 7.5; $0.ry = 7; $0.head = 0x2A2430; $0.limb = 0x2A2430; $0.glossy = true; $0.eyeStyle = .light; $0.eye = 0x2A2430
        $0.back = [shellWings(0xE8433A, 0xEAF8FF)]
        $0.surface = [spots(0x1E1A22, [(-0.55, 0.3, 1.3), (0.55, 0.25, 1.3), (-0.3, 0.75, 1.0), (0.35, 0.72, 1.0)]), shellLine()]
        $0.top = [antennae(.ball, 0x2A2430)]
        $0.feet = .insect; $0.flies = true; $0.special = "sparkle"
    },
    species("prayla", "Prayla", "dusk", "insect", main: 0x8C9BE0, "A periwinkle mantis that folds its arms and says grace before every single snack.") {
        $0.body = .egg; $0.rx = 6.8; $0.ry = 7.4; $0.belly = 0xD6DCF8; $0.eye = 0x3A2A10; $0.eyeStyle = .bug(0xFFC94A); $0.noArms = true; $0.limb = 0x6F7FC8
        $0.back = [laceLobes(0xDCE2FA)]
        $0.top = [antennae(.long, 0x4A5AA0)]
        $0.front = [scytheArms(0x6F7FC8)]
        $0.feet = .insect; $0.special = "sparkle"; $0.walkSpeed = 50
    },
    species("lumbug", "Lumbug", "glow", "insect", main: 0x3A3550, "A firefly whose lantern glows brighter when it's excited and dims to a nightlight when it sleeps.") {
        $0.body = .bugHead; $0.rx = 6.5; $0.ry = 6.5; $0.head = 0x1E1B2A; $0.limb = 0x1E1B2A; $0.eyeStyle = .light; $0.eye = 0x1E1B2A
        $0.back = [lanternTail(0xE8FF7A), beeWings(0xD8E0FF)]
        $0.top = [antennae(.ball, 0x1E1B2A, tip: 0xE8FF7A)]
        $0.feet = .insect; $0.flies = true; $0.special = "glow"
    },
    species("lunette", "Lunette", "moon", "insect", main: 0xF4F7EC, "A pale luna moth with long ribbon tails. Only comes out to dance under the moon.") {
        $0.rx = 6.2; $0.ry = 6.4; $0.eye = 0x2A3A1E; $0.cheek = 0xFFB3C6; $0.fluffy = true
        $0.back = [mothWings(0xB9F0A8, 0xF2C14E, tails: true)]
        $0.top = [antennae(.feather, 0xF2C14E)]
        $0.flies = true; $0.special = "glow"
    },
    species("woolybit", "Woolybit", "weather", "insect", main: 0x2A2420, "A woolly bear caterpillar. The width of its orange band predicts the winter, supposedly.") {
        $0.rx = 6.6; $0.ry = 6.4; $0.eye = 0x2A2420; $0.eyeStyle = .light; $0.noArms = true; $0.fluffy = true
        $0.back = [caterpillarSegments([0xD9732E, 0xD9732E, 0x2A2420])]
        $0.feet = .insect; $0.special = "sparkle"; $0.walkSpeed = 30
    },
    species("peacockle", "Peacockle", "display", "insect", main: 0x2A2A3A, "A peacock spider. It unfurls a rainbow fan and dances for anyone who'll watch.") {
        $0.rx = 6.2; $0.ry = 5.8; $0.eye = 0x2A2A3A; $0.eyeStyle = .light; $0.noArms = true; $0.feet = .none
        $0.back = [fanDisplay(0x3FA6E0, 0xF28A3A, 0xE0465A), spiderLegs(0x3A3A4A)]
        $0.surface = [spiderSideEyes]
        $0.special = "notes"; $0.walkSpeed = 85; $0.jumpPower = 1.5
    },
    species("fiddlet", "Fiddlet", "song", "insect", main: 0x7DB84A, "A cricket that chirps the same three-note song every evening, and is very proud of it.") {
        $0.body = .egg; $0.rx = 6.6; $0.ry = 7; $0.belly = 0xD8EFA0; $0.eye = 0x1E2A10
        $0.back = [hopLegs(0x5E9A34)]
        $0.top = [antennae(.long, 0x3E6A22)]
        $0.feet = .insect; $0.special = "notes"; $0.jumpPower = 1.5
    },
    species("prismite", "Prismite", "prism", "insect", main: 0x2E9AA8, "A jewel beetle whose shell throws tiny rainbows on the wall whenever the sun hits it.") {
        $0.rx = 7.2; $0.ry = 6.6; $0.eye = 0x0E2A2E; $0.glossy = true; $0.limb = 0x1F6A75
        $0.surface = [shellLine(), spots(0xF2C14E, [(-0.6, 0.2, 0.8), (0.6, 0.2, 0.8), (-0.3, 0.65, 0.6), (0.3, 0.65, 0.6)])]
        $0.top = [noseHorn(0xF2C14E)]
        $0.feet = .insect; $0.special = "sparkle"; $0.walkSpeed = 45
    },
    species("snipleaf", "Snipleaf", "colony", "insect", main: 0xA0482A, "A leafcutter ant that can lift ten times its weight and loves to show off.") {
        $0.body = .bugHead; $0.rx = 6.5; $0.ry = 6.5; $0.head = 0xB8582E; $0.limb = 0x7A3018; $0.eye = 0x2A0E06
        $0.muzzle = mandibles(0x5A2412)
        $0.top = [antennae(.elbow, 0x5A2412)]
        $0.feet = .insect; $0.special = "leaves"; $0.walkSpeed = 75
    },

    // ---------------------------------------------------------------- Dragons
    species("kumoryu", "Kumoryu", "cloud", "dragon", main: 0xFF8E7A, "A coral sky-dragon that coils up like a cinnamon roll to nap.") {
        $0.body = .coil; $0.rx = 8; $0.ry = 8.5; $0.head = 0xFF9E8A; $0.eye = 0x2A1414; $0.mouthDY = 4; $0.feet = .none
        $0.surface = [bellyScales(0xFFE3C8)]
        $0.muzzle = snout(0xFFD0BC, nose: 0x8A3A2A, w: 0.4)
        $0.top = [antlers(0xF2C14E), whiskers(0xF2C14E, long: true)]
        $0.flies = true; $0.special = "clouds"
    },
    species("mintwyrm", "Mintwyrm", "jasmine", "dragon", main: 0x9FE0C5, "A tiny mint-green wyrm that smells faintly of jasmine tea.") {
        $0.rx = 6.2; $0.ry = 6; $0.belly = 0xF2FFF6; $0.eye = 0x1A3A2A
        $0.back = [batWings(0x7FCFB0, 0x4FA58A), curvedHorns(0xF2E2B0)]
        $0.special = "steam"; $0.walkSpeed = 35; $0.jumpPower = 0.9
    },
    species("gemscale", "Gemscale", "crystal", "dragon", main: 0xD6E2F5, "A moonstone dragon that grows crystals instead of spikes. They chime when it runs.") {
        $0.body = .egg; $0.rx = 7.4; $0.ry = 7.4; $0.eye = 0x1E2A4A
        $0.back = [batWings(0xA8B8E0, 0x6A7AA8), lizardTail(0xD6E2F5, tip: .spikes(0xB49CFF)), crystals(0xB49CFF)]
        $0.surface = [bellyScales(0xF4F8FF)]
        $0.feet = .big; $0.flies = true; $0.special = "sparkle"
    },
    species("mossmaw", "Mossmaw", "ancient", "dragon", main: 0x7E9F5A, "An old, sleepy dragon so still that moss and flowers grow on its back.") {
        $0.body = .pear; $0.rx = 9; $0.ry = 8; $0.eye = 0x1E2A10; $0.restEyes = .sleepy
        $0.back = [curvedHorns(0xB08A5A), lizardTail(0x7E9F5A, tip: .leaf(0x5FAF4A), thick: 1.2)]
        $0.surface = [bellyScales(0xD9E6A8), moss(0x5FAF4A)]
        $0.feet = .big; $0.special = "petals"; $0.walkSpeed = 35; $0.sleepiness = 1.9; $0.jumpPower = 0.75
    },
    species("pipwyrn", "Pipwyrn", "mischief", "dragon", main: 0xE05FA8, "A pocket wyvern with a fang-y grin. Hides things, then helps you look for them.") {
        $0.rx = 6.6; $0.ry = 6.4; $0.belly = 0xFFE07A; $0.eye = 0x3A0E2A; $0.fangs = true
        $0.back = [batWings(0x7A3A8A, 0x4A1E5A), lizardTail(0xE05FA8, tip: .tuft(0xFFE07A), len: 0.9)]
        $0.top = [hornNubs(0xFFE3F2)]
        $0.flies = true; $0.special = "smoke"; $0.walkSpeed = 85
    },
    species("ashlet", "Ashlet", "ember", "dragon", main: 0x3A3440, "A charcoal dragonling with glowing cracks. Hiccups little sparks when it laughs.") {
        $0.body = .egg; $0.rx = 7.4; $0.ry = 7.2; $0.eye = 0x2A1A10; $0.eyeStyle = .glow(0xFF9A3D)
        $0.back = [batWings(0x4A4250, 0x2A2430), lizardTail(0x3A3440, tip: .ember), curvedHorns(0x6A6070)]
        $0.surface = [bellyScales(0x5A5260), cracks(0xFF8A3D)]
        $0.feet = .big; $0.flies = true; $0.special = "fire"
    },

    // ---------------------------------------------------------------- Dinosaurs
    species("trikit", "Trikit", "stone", "dino", main: 0x5FB89A, "A baby triceratops whose frill blushes orange when it gets excited.") {
        $0.body = .egg; $0.rx = 8.4; $0.ry = 7; $0.belly = 0xD9F2E6; $0.eye = 0x1A2A22; $0.mouthDY = 4
        $0.back = [frill(0xF2A65A, 0xFFE0A8), lizardTail(0x5FB89A, thick: 1.1, len: 0.8)]
        $0.muzzle = bigSnout(0x7CCFB2)
        $0.top = [hornNubs(0xFFF4DC, spread: 0.38, height: 4.2), noseHorn(0xFFF4DC)]
        $0.feet = .big; $0.special = "stomp"; $0.walkSpeed = 55
    },
    species("stegglet", "Stegglet", "fern", "dino", main: 0x9CC85A, "A stegosaurus hatchling whose back plates are shaped like autumn leaves.") {
        $0.body = .egg; $0.rx = 8; $0.ry = 7; $0.belly = 0xF0F2C0; $0.eye = 0x1E2A10; $0.mouthDY = 4
        $0.back = [plates(0xE8784A, leafy: true), lizardTail(0x9CC85A, tip: .spikes(0xF2E2C0))]
        $0.muzzle = bigSnout(0xB4D879)
        $0.feet = .big; $0.special = "leaves"; $0.walkSpeed = 50
    },
    species("rexlet", "Rexlet", "thunder", "dino", main: 0x4FA3D9, "A tiny tyrannosaur with a huge roar and arms too short to hug. It tries anyway.") {
        $0.body = .pear; $0.rx = 8.5; $0.ry = 8; $0.belly = 0xD6EEFA; $0.eye = 0x0E2A40; $0.fangs = true; $0.mouthDY = 4
        $0.back = [lizardTail(0x4FA3D9, thick: 1.3)]
        $0.surface = [spots(0x2F7FB8, [(-0.75, -0.2, 0.8), (0.75, -0.25, 0.8), (-0.6, 0.25, 0.7), (0.62, 0.2, 0.7)])]
        $0.muzzle = bigSnout(0x6FB8E6)
        $0.feet = .big; $0.special = "roar"; $0.walkSpeed = 65
    },
    species("brontle", "Brontle", "meadow", "dino", main: 0x9FB7D9, "A long-necked dinosaur who can see over every window. Very gentle, always chewing.") {
        $0.body = .longneck; $0.rx = 9; $0.ry = 7.2; $0.eye = 0x1A2A40; $0.faceV = -0.05; $0.eyeGap = 0.42; $0.noArms = true
        $0.back = [lizardTail(0x9FB7D9, len: 1.2)]
        $0.surface = [bellyScales(0xE6EEF8), spots(0x7F9AC4, [(-0.6, 0.3, 1.0), (-0.2, 0.5, 0.9), (-0.85, 0.55, 0.7)])]
        $0.feet = .big; $0.special = "leaves"; $0.walkSpeed = 40; $0.jumpPower = 0.7
    },
    species("pteribit", "Pteribit", "updraft", "dino", main: 0xF29C6B, "A peach pterosaur chick with a swept-back crest. Glides better than it flaps.") {
        $0.rx = 6.6; $0.ry = 6.4; $0.belly = 0xFFE0C8; $0.eye = 0x2A140A; $0.beak = true; $0.mouthDY = 4
        $0.back = [batWings(0xF2B08A, 0xC8704A), crest(0xE0603A)]
        $0.muzzle = beak(0xFFD08A, .long)
        $0.feet = .talons(0xD08A4A); $0.flies = true; $0.special = "sparkle"
    },
    species("ankylet", "Ankylet", "pinecone", "dino", main: 0xA07850, "An armoured ankylosaur covered in pinecone scales. Its tail club makes a great drum.") {
        $0.body = .pebble; $0.rx = 9.5; $0.ry = 6.4; $0.eye = 0x1E140A; $0.mouthDY = 4
        $0.back = [lizardTail(0xA07850, tip: .club(0x7A5A3A), thick: 1.2, len: 0.9), backSpikes(0xF2E2C0)]
        $0.surface = [scales(0x7A5A3A)]
        $0.muzzle = snout(0xC8A078, nose: 0x4A3020, w: 0.3)
        $0.feet = .big; $0.special = "stomp"; $0.walkSpeed = 35; $0.jumpPower = 0.75
    },
    species("bonkle", "Bonkle", "boulder", "dino", main: 0xC7D86A, "A dome-headed dinosaur that greets friends with a gentle bonk.") {
        $0.body = .egg; $0.rx = 7.6; $0.ry = 7.6; $0.belly = 0xF4F6D0; $0.eye = 0x1E2A0A; $0.faceV = 0.02; $0.mouthDY = 4
        $0.back = [lizardTail(0xC7D86A, len: 0.9)]
        $0.muzzle = snout(0xDAE68E, w: 0.32)
        $0.top = [domeHead(0xF0E2C0, 0xB0A080)]
        $0.feet = .big; $0.special = "bonk"; $0.walkSpeed = 60
    },

    // ---------------------------------------------------------------- Mythical beasts
    species("griffet", "Griffet", "gale", "mythic", main: 0xD9A866, "A griffin chick: eagle up front, lion in the back, all fluff in the middle.") {
        $0.rx = 7.2; $0.ry = 7; $0.eye = 0x2A1A0A; $0.beak = true; $0.mouthDY = 4
        $0.back = [birdWings(0xB07840, 0xF7F2E8), thinTail(0xD9A866, tuft: 0x8A5A2A)]
        $0.surface = [twoTone(0xF7F2E8, below: -0.05)]
        $0.muzzle = beak(0xF2B82E, .hook)
        $0.top = [tuft(0xF7F2E8)]
        $0.feet = .talons(0xF2B82E); $0.flies = true; $0.special = "sparkle"
    },
    species("wolpy", "Wolpy", "folklore", "mythic", main: 0xC08A55, "A squirrel that grew tiny antlers. Nobody believes it exists.") {
        $0.body = .egg; $0.rx = 7; $0.ry = 7.2; $0.belly = 0xF2DCC0; $0.eye = 0x2A1A0A; $0.mouthDY = 4
        $0.back = [bushyTail(0xC08A55, big: 1.15), antlers(0x8A6A4A)]
        $0.muzzle = snout(0xF2DCC0, nose: 0x4A2A1A, w: 0.28)
        $0.special = "sparkle"; $0.walkSpeed = 80
    },
    species("yetini", "Yetini", "blizzard", "mythic", main: 0xEAF2FF, "A yeti cub with big feet and a soft, shy face. Leaves tiny footprints nobody can explain.") {
        $0.rx = 8; $0.ry = 7.6; $0.eye = 0x2A3050; $0.fluffy = true; $0.eyeStyle = .light
        $0.back = [roundEars(0x7F8FB8, size: 0.6, spread: 0.7)]
        $0.surface = [facePatch(0x7F8FB8, w: 0.72, h: 0.62)]
        $0.feet = .big; $0.special = "snow"; $0.walkSpeed = 55
    },
    species("nessle", "Nessle", "loch", "mythic", main: 0x6E8F5A, "A shy lake monster that pops up wherever there's a puddle. Blurry in every photo.") {
        $0.body = .longneck; $0.rx = 8; $0.ry = 6.5; $0.eye = 0x0E2A26; $0.faceV = -0.05; $0.noArms = true; $0.feet = .none
        $0.back = [humps()]
        $0.surface = [spots(0x4F6E40, [(-0.5, 0.25, 1.0), (-0.05, 0.4, 0.8)])]
        $0.front = [ripples()]
        $0.special = "bubbles"; $0.walkSpeed = 45
    },
    species("inklet", "Inklet", "deep", "mythic", main: 0xC77DD1, "A baby kraken that squirts a little ink when it gets startled.") {
        $0.rx = 8; $0.ry = 7.6; $0.eye = 0x2A0E30; $0.glossy = true; $0.noArms = true; $0.feet = .none
        $0.surface = [spots(0xE8B0F0, [(-0.6, -0.4, 1.0), (0.55, -0.55, 0.8), (0.7, 0.1, 0.7), (-0.75, 0.15, 0.6)])]
        $0.front = [tentacles()]
        $0.special = "ink"; $0.walkSpeed = 50
    },
    species("tripup", "Tripup", "underworld", "mythic", main: 0x4A4258, "A three-headed puppy that guards nothing in particular. All three heads want belly rubs.") {
        $0.body = .pear; $0.rx = 7; $0.ry = 7.4; $0.eye = 0x1E1A24; $0.eyeStyle = .light; $0.mouthDY = 4; $0.noArms = true
        $0.back = [fawnEars(0x6A6080), thinTail()]
        $0.front = [extraHeads(0x2A2438)]
        $0.muzzle = snout(0x8A80A0, nose: 0x1E1A24, w: 0.3)
        $0.special = "bark"; $0.walkSpeed = 75
    },
    species("sphinxie", "Sphinxie", "riddle", "mythic", main: 0xE8C27A, "A winged sand-kitten that asks riddles and forgets the answers.") {
        $0.rx = 7.4; $0.ry = 7; $0.eye = 0x2A1A0A; $0.mouthDY = 4
        $0.back = [birdWings(0xF2D08A, 0xC89A4A), catEars(0xF7E2B8), thinTail(0xE8C27A, tuft: 0xB07840)]
        $0.muzzle = snout(0xF7E2B8, nose: 0xB06040, w: 0.3)
        $0.flies = true; $0.special = "sparkle"; $0.walkSpeed = 60
    },
    species("cockatrix", "Cockatrix", "basilisk", "mythic", main: 0xFFF1C9, "A cockatrice chick: half chick, half lizard, all attitude. Its glare is mostly bluff.") {
        $0.rx = 7; $0.ry = 6.8; $0.eye = 0x2A1A0A; $0.beak = true; $0.fluffy = true; $0.mouthDY = 4
        $0.back = [birdWings(0xF7E2A0, 0xE8C27A), lizardTail(0x5FA85A, len: 1.0)]
        $0.muzzle = beak(0xF2A62E)
        $0.top = [comb(0xE0465A)]
        $0.feet = .talons(0xF2A62E); $0.special = "sparkle"; $0.walkSpeed = 70
    },
]
