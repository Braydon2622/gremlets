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
    // ---------------------------------------------------------------- Approved by Braydon (design review, 2026-11-05)
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
    species("gumleaf", "Gumleaf", "eucalyptus", "animal", main: 0xB7B2AC, "A very fluffy koala who insists on being called Your Fluffiness.") {
        $0.rx = 8; $0.ry = 7.2; $0.belly = 0xF6F2EC; $0.eye = 0x1E1E24; $0.mouthDY = 5; $0.fluffy = true
        $0.back = [roundEars(0xF6F2EC, size: 1.45, spread: 0.75)]
        $0.muzzle = koalaNose()
        $0.special = "petals"; $0.walkSpeed = 45; $0.sleepiness = 1.3
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
    species("mintwyrm", "Mintwyrm", "jasmine", "dragon", main: 0x9FE0C5, "A tiny mint-green wyrm that smells faintly of jasmine tea.") {
        $0.rx = 6.2; $0.ry = 6; $0.belly = 0xF2FFF6; $0.eye = 0x1A3A2A
        $0.back = [batWings(0x7FCFB0, 0x4FA58A), curvedHorns(0xF2E2B0)]
        $0.special = "steam"; $0.walkSpeed = 35; $0.jumpPower = 0.9
    },

    // ---------------------------------------------------------------- Mythical beasts (v2: softer, simpler)
    species("nessle", "Nessle", "loch", "mythic", main: 0x6FB59A, "A shy lake monster that pops up wherever there's a puddle. Blurry in every photo.") {
        $0.body = .longneck; $0.rx = 8.4; $0.ry = 6.8; $0.eye = 0x12302A; $0.faceV = -0.05; $0.noArms = true; $0.feet = .none
        $0.back = [humps(), neckFins(0x4F9A80)]
        $0.surface = [bellyScales(0xE8F4D8), spots(0x5A9E84, [(-0.55, 0.25, 0.9), (-0.85, 0.5, 0.7)])]
        $0.top = [hornNubs(0xE8F4D8, spread: 0.3, height: 2.2)]
        $0.front = [ripples()]
        $0.special = "bubbles"; $0.walkSpeed = 45
    },
    species("griffet", "Griffet", "gale", "mythic", main: 0xE2B86E, "A griffin chick: eagle up front, lion in the back, all fluff in the middle.") {
        $0.rx = 7.4; $0.ry = 7.2; $0.eye = 0x2A1A0A; $0.beak = true; $0.mouthDY = 4; $0.fluffy = true; $0.cheek = 0xFFB08A
        $0.back = [birdWings(0xC8945A, 0xFFF4E0), thinTail(0xE2B86E, tuft: 0x9A6A3A)]
        $0.surface = [twoTone(0xFFF8EC, below: -0.15)]
        $0.muzzle = beak(0xF2B82E, .hook)
        $0.feet = .talons(0xF2B82E); $0.flies = true; $0.special = "sparkle"
    },
    species("yetini", "Yetini", "blizzard", "mythic", main: 0xF4F8FF, "A yeti cub with big soft feet. Leaves tiny footprints nobody can explain.") {
        $0.rx = 8; $0.ry = 7.6; $0.eye = 0x24304A; $0.fluffy = true; $0.cheek = 0xA9C9FF; $0.limb = 0xE6EEFA
        $0.back = [roundEars(0xC8D6EE, size: 0.6, spread: 0.7)]
        $0.surface = [facePatch(0xD6E2F5, w: 0.66, h: 0.55)]
        $0.feet = .big; $0.special = "snow"; $0.walkSpeed = 55
    },
    species("inklet", "Inklet", "deep", "mythic", main: 0xD9A6E8, "A baby kraken that squirts a little ink when it gets startled.") {
        $0.rx = 7.8; $0.ry = 7.6; $0.eye = 0x2A0E30; $0.glossy = true; $0.noArms = true; $0.feet = .none; $0.cheek = 0xFF8FB8
        $0.surface = [spots(0xF2D6F8, [(-0.55, -0.45, 1.1), (0.5, -0.6, 0.8), (0.7, 0.0, 0.7)])]
        $0.front = [tentacles()]
        $0.special = "ink"; $0.walkSpeed = 50
    },
    species("qiru", "Qiru", "auspice", "mythic", main: 0xF2DDB0, "A qilin foal with jade scales and a cloud-puff tail. Little flowers bloom where it steps.") {
        $0.body = .egg; $0.rx = 7.4; $0.ry = 7.2; $0.belly = 0xFFF6E2; $0.eye = 0x2A2010; $0.mouthDY = 4; $0.cheek = 0xFFA8A0
        $0.back = [fawnEars(0xF7C9B0), puffTail(0xFFFFFF)]
        $0.surface = [spots(0x7CC4A0, [(-0.7, -0.15, 0.9), (-0.45, -0.5, 0.8), (0.55, -0.45, 0.8), (0.75, -0.1, 0.8)])]
        $0.muzzle = snout(0xFFF6E2, nose: 0x6A4A3A)
        $0.top = [hornNubs(0x7CC4A0, spread: 0.0, height: 4.0)]
        $0.feet = .hooves(0x7A5A40); $0.special = "petals"; $0.walkSpeed = 75; $0.jumpPower = 1.2
    },
    species("selkip", "Selkip", "tide", "mythic", main: 0xB8C2CC, "A selkie pup: a seal on the beach, a story by the fire. Mostly it just naps on warm rocks.") {
        $0.body = .egg; $0.rx = 8.4; $0.ry = 6.8; $0.belly = 0xEEF2F6; $0.eye = 0x1A2028; $0.mouthDY = 4; $0.feet = .none; $0.limb = 0xA0AAB6; $0.cheek = 0xFFA8B8
        $0.back = [lizardTail(0xB8C2CC, tip: .fluke(0xA0AAB6), len: 0.6)]
        $0.surface = [spots(0x8A96A2, [(-0.6, -0.35, 0.7), (0.5, -0.5, 0.6), (-0.3, -0.7, 0.5), (0.7, 0.05, 0.6)])]
        $0.muzzle = snout(0xEEF2F6, nose: 0x2A2A30, w: 0.36)
        $0.top = [whiskers(0xFFFFFF)]
        $0.special = "bubbles"; $0.walkSpeed = 40; $0.sleepiness = 1.4
    },
    species("skyfoal", "Skyfoal", "breeze", "mythic", main: 0xF7F1E6, "A pegasus foal still learning to fly. Mostly it does very tall hops.") {
        $0.body = .egg; $0.rx = 7; $0.ry = 7.2; $0.eye = 0x2A2438; $0.mouthDY = 4; $0.cheek = 0xFFB0C0
        $0.back = [birdWings(0xD6CCF6, 0xB2A6EC), fawnEars(0xF2C9D0)]
        $0.muzzle = snout(0xFFFFFF, nose: 0x8A7A9A, w: 0.36)
        $0.top = [tuft(0xC9B6F2)]
        $0.feet = .hooves(0x9A8AB0); $0.flies = true; $0.special = "sparkle"; $0.jumpPower = 1.35
    },
    species("hopalope", "Hopalope", "prairie", "mythic", main: 0xC9A27A, "A jackalope: a rabbit with tiny antlers. Shy, fast, and absolutely real.") {
        $0.rx = 7.2; $0.ry = 7; $0.belly = 0xF6E8D6; $0.eye = 0x2A1A0E; $0.mouthDY = 4
        $0.back = [antlers(0x8A6A4A), longEars(0xF2C0B0), puffTail(0xFFF6EC)]
        $0.muzzle = snout(0xF6E8D6, nose: 0xC07070, w: 0.26)
        $0.special = "sparkle"; $0.walkSpeed = 80; $0.jumpPower = 1.3
    },

    // ---------------------------------------------------------------- Countryside, forest, sea and sky (Ghibli-inspired)
    species("dormie", "Dormie", "hedgerow", "animal", main: 0xE0A85A, "A golden dormouse that sleeps curled in its own tail for most of the year.") {
        $0.rx = 7; $0.ry = 6.8; $0.belly = 0xFFF0D8; $0.eye = 0x24160A; $0.mouthDY = 4
        $0.back = [roundEars(0xF7C0A8, size: 1.15), bushyTail(0xE0A85A, big: 0.95)]
        $0.muzzle = snout(0xFFF0D8, nose: 0xD07080, w: 0.24)
        $0.top = [whiskers(0xFFFFFF)]
        $0.special = "seeds"; $0.sleepiness = 2.0; $0.walkSpeed = 65
    },
    species("drizzlefox", "Drizzlefox", "rain", "animal", main: 0x9FB4CC, "A blue-grey fox kit that only comes out when it rains. Its freckles look like raindrops.") {
        $0.rx = 7; $0.ry = 6.8; $0.belly = 0xF2F6FA; $0.eye = 0x1A2438; $0.mouthDY = 4
        $0.back = [catEars(0xF2F6FA, size: 1.2), bushyTail(0x9FB4CC, tip: 0xFFFFFF)]
        $0.surface = [freckles(0x6FB8F0)]
        $0.muzzle = snout(0xF2F6FA, nose: 0x2A3040, w: 0.3)
        $0.special = "rain"; $0.walkSpeed = 80
    },
    species("wombloom", "Wombloom", "meadow", "animal", main: 0xA88C70, "A wombat so still and sunny that a little meadow grows on its back.") {
        $0.body = .pebble; $0.rx = 9; $0.ry = 6.6; $0.eye = 0x22160C; $0.mouthDY = 4
        $0.back = [roundEars(0x8A7058, size: 0.7, spread: 0.6)]
        $0.surface = [moss(0x8FCB6A, flower: 0xFFE38A)]
        $0.muzzle = snout(0xC8B098, nose: 0x3A2618, w: 0.32)
        $0.special = "petals"; $0.walkSpeed = 40; $0.jumpPower = 0.75
    },
    species("calicat", "Calicat", "hearth", "animal", main: 0xFFF8F0, "A calico kitten that naps in every sunbeam and chases every dust mote.") {
        $0.rx = 7.2; $0.ry = 6.8; $0.eye = 0x2A2010; $0.cheek = 0xFFA8B8
        $0.back = [catEars(0xF7C0C8), curlTail(0xE8963A)]
        $0.surface = [spots(0xE8963A, [(-0.6, -0.5, 2.2), (0.65, 0.4, 1.9)]), spots(0x3A3434, [(0.6, -0.6, 1.6), (-0.72, 0.45, 1.3)])]
        $0.special = "sparkle"; $0.walkSpeed = 75; $0.jumpPower = 1.25
    },
    species("shibun", "Shibun", "village", "animal", main: 0xE8A25A, "A shiba pup with a curly tail and a smile that never quite turns off.") {
        $0.rx = 7.2; $0.ry = 6.8; $0.belly = 0xFFF6E8; $0.eye = 0x24140A; $0.mouthDY = 4
        $0.back = [catEars(0xFFF6E8, size: 0.95), curlTail(0xE8A25A)]
        $0.surface = [facePatch(0xFFF6E8, w: 0.55, h: 0.3)]
        $0.muzzle = snout(0xFFF6E8, nose: 0x2A1A10, w: 0.3)
        $0.special = "bark"; $0.walkSpeed = 80
    },
    species("truffet", "Truffet", "woodland", "animal", main: 0xF4B8B4, "A piglet with a mossy back that snuffles out mushrooms nobody else can find.") {
        $0.rx = 7.6; $0.ry = 6.8; $0.eye = 0x2A1418; $0.mouthDY = 4; $0.cheek = 0xFF8FA0
        $0.back = [fawnEars(0xE89A9A), curlTail(0xF4B8B4)]
        $0.surface = [moss(0x8FCB6A)]
        $0.muzzle = bigSnout(0xF7A0A6)
        $0.special = "leaves"; $0.walkSpeed = 55
    },
    species("billet", "Billet", "hillside", "animal", main: 0xF7F4EE, "A goat kid that climbs everything, especially the things it shouldn't.") {
        $0.body = .egg; $0.rx = 6.8; $0.ry = 7.2; $0.eye = 0x3A2A14; $0.mouthDY = 4; $0.cheek = 0xFFB0B8
        $0.back = [curvedHorns(0xC8B89A), fawnEars(0xF2D6C8)]
        $0.muzzle = snout(0xFFFFFF, nose: 0x8A6A5A, w: 0.32)
        $0.top = [beard(0xF2EEE6)]
        $0.feet = .hooves(0x6A5A4A); $0.special = "sparkle"; $0.walkSpeed = 70; $0.jumpPower = 1.45
    },
    species("honklet", "Honklet", "millpond", "animal", main: 0xD8D2B8, "A fluffy gosling that follows whoever it saw first. Today that's you.") {
        $0.rx = 6.8; $0.ry = 6.8; $0.belly = 0xF6F2DC; $0.eye = 0x1A1A14; $0.beak = true; $0.mouthDY = 4; $0.fluffy = true
        $0.back = [birdWings(0xC2BC9E, 0xA8A288)]
        $0.muzzle = beak(0x7A7058, .short)
        $0.feet = .webbed(0x4A4A44); $0.special = "notes"; $0.walkSpeed = 60
    },
    species("bramblet", "Bramblet", "hedgerow", "animal", main: 0x9A9AA0, "A badger cub that digs tunnels under the hedgerow and invites everyone over.") {
        $0.body = .pebble; $0.rx = 8.4; $0.ry = 6.6; $0.belly = 0x5A5A62; $0.eye = 0x14141A; $0.limb = 0x3A3A42; $0.mouthDY = 4; $0.eyeStyle = .light
        $0.back = [roundEars(0xF2F2F2, size: 0.6, spread: 0.55)]
        $0.surface = [badgerStripes(0xF7F7F4, 0x2E2E36)]
        $0.muzzle = snout(0xF7F7F4, nose: 0x1E1E24, w: 0.26)
        $0.special = "leaves"; $0.walkSpeed = 55
    },
    species("skyfin", "Skyfin", "sky", "animal", main: 0x9CC8EC, "A baby sky whale that swims through the air and sings to the clouds.") {
        $0.body = .pebble; $0.rx = 9.4; $0.ry = 6.2; $0.eye = 0x14283A; $0.feet = .none; $0.floats = true; $0.limb = 0x7EB0DA; $0.cheek = 0xFFB0C8
        $0.back = [lizardTail(0x9CC8EC, tip: .fluke(0x7EB0DA), thick: 1.2, len: 0.85)]
        $0.surface = [bellyScales(0xEEF6FC)]
        $0.flies = true; $0.special = "notes"; $0.walkSpeed = 45
    },
    species("ermelin", "Ermelin", "winter", "animal", main: 0xFBFBF8, "A stoat in its white winter coat. Only the tip of its tail stays black.") {
        $0.body = .pear; $0.rx = 6.4; $0.ry = 7.4; $0.eye = 0x14141A; $0.mouthDY = 4; $0.cheek = 0xFFB8C0
        $0.back = [roundEars(0xF7D0D0, size: 0.75, spread: 0.6), thinTail(0xFBFBF8, tuft: 0x2A2A30)]
        $0.muzzle = snout(0xFFFFFF, nose: 0x2A2028, w: 0.26)
        $0.special = "snow"; $0.walkSpeed = 90; $0.jumpPower = 1.3
    },
    species("wrenlet", "Wrenlet", "thicket", "animal", main: 0xB8865A, "A round little wren with its tail cocked high. Sings far too loudly for its size.") {
        $0.rx = 6.4; $0.ry = 6.2; $0.belly = 0xF2DCC0; $0.eye = 0x1E140A; $0.beak = true; $0.mouthDY = 3; $0.fluffy = true
        $0.back = [birdWings(0x9A6E48, 0xD8B890), featherTail(0x9A6E48, 0x7A5436)]
        $0.surface = [browDots(0xF2DCC0)]
        $0.muzzle = beak(0x5A4430)
        $0.feet = .talons(0xC89A70); $0.flies = true; $0.special = "notes"; $0.walkSpeed = 70
    },
    species("snowpaw", "Snowpaw", "summit", "animal", main: 0xE8E6E2, "A snow leopard cub with a tail almost as long as the rest of it.") {
        $0.rx = 7.2; $0.ry = 6.8; $0.belly = 0xFAFAF8; $0.eye = 0x2A3A30; $0.mouthDY = 4
        $0.back = [roundEars(0xF2D8D8, size: 0.8, spread: 0.62), bushyTail(0xE8E6E2, ring: 0x8A8A90, big: 1.05)]
        $0.surface = [spots(0x8A8A90, [(-0.7, -0.3, 0.8), (0.65, -0.45, 0.8), (-0.4, -0.75, 0.6), (0.78, 0.15, 0.7), (-0.82, 0.25, 0.6)])]
        $0.muzzle = snout(0xFAFAF8, nose: 0xD08A90, w: 0.28)
        $0.special = "snow"; $0.walkSpeed = 75; $0.jumpPower = 1.3
    },
    species("lynxie", "Lynxie", "pinewood", "animal", main: 0xD6B48A, "A lynx kit with fancy ear tufts and enormous paws it hasn't grown into yet.") {
        $0.rx = 7.2; $0.ry = 6.8; $0.belly = 0xF6EAD8; $0.eye = 0x3A2A10; $0.mouthDY = 4; $0.feet = .big
        $0.back = [catEars(0xF6EAD8, size: 1.05), earTufts(0x3A2A1A), puffTail(0x3A2A1A)]
        $0.surface = [spots(0xB08A60, [(-0.7, -0.25, 0.6), (0.7, -0.35, 0.6), (-0.5, 0.35, 0.5)])]
        $0.muzzle = snout(0xF6EAD8, nose: 0xC07A6A, w: 0.3)
        $0.special = "sparkle"; $0.walkSpeed = 70
    },
    species("moosling", "Moosling", "fen", "animal", main: 0x9A7458, "A gangly moose calf that's mostly legs and nose. Its antlers are still velvet nubs.") {
        $0.body = .egg; $0.rx = 7.2; $0.ry = 7.4; $0.eye = 0x1E140A; $0.mouthDY = 5
        $0.back = [hornNubs(0xC8A880, spread: 0.45, height: 2.4), fawnEars(0xB89070)]
        $0.muzzle = bigSnout(0xB89070)
        $0.feet = .hooves(0x4A3424); $0.special = "leaves"; $0.walkSpeed = 55
    },
    species("paddlebill", "Paddlebill", "creek", "animal", main: 0x9A7050, "A platypus that can't decide if it's a duck, a beaver or an otter, and is happy being all three.") {
        $0.body = .pebble; $0.rx = 8.6; $0.ry = 6.2; $0.belly = 0xD8B898; $0.eye = 0x1E140A; $0.beak = true; $0.mouthDY = 4
        $0.back = [lizardTail(0x7A5638, thick: 1.4, len: 0.6)]
        $0.muzzle = beak(0x4A4A50, .bill)
        $0.feet = .webbed(0x4A4A50); $0.special = "bubbles"; $0.walkSpeed = 50
    },
    species("pangle", "Pangle", "savanna", "animal", main: 0xC8A070, "A baby pangolin covered in pinecone scales. Rolls into a ball when it's shy.") {
        $0.body = .egg; $0.rx = 7.2; $0.ry = 7; $0.belly = 0xF2DCC0; $0.eye = 0x24160A; $0.mouthDY = 4
        $0.back = [lizardTail(0xB08A5A, thick: 1.3, len: 0.85)]
        $0.surface = [scales(0x9A7448)]
        $0.muzzle = snout(0xF2DCC0, nose: 0x6A4A3A, w: 0.26)
        $0.special = "leaves"; $0.walkSpeed = 45
    },
    species("quokkly", "Quokkly", "island", "animal", main: 0xB89A78, "A quokka with the happiest face on the island. Nobody knows what it's smiling about.") {
        $0.body = .pear; $0.rx = 7.2; $0.ry = 7.2; $0.belly = 0xE8D6C0; $0.eye = 0x1E140A; $0.mouthDY = 4; $0.restEyes = .happy
        $0.back = [roundEars(0x9A7A60, size: 0.75, spread: 0.6), thinTail(0x9A7A60)]
        $0.muzzle = snout(0xE8D6C0, nose: 0x2A1A14, w: 0.28)
        $0.special = "sparkle"; $0.walkSpeed = 70; $0.jumpPower = 1.2
    },
    species("thrumlet", "Thrumlet", "garden", "animal", main: 0x5FC2A2, "A hummingbird that hovers in place to say hello, then zips off mid-sentence.") {
        $0.rx = 5.8; $0.ry = 5.8; $0.belly = 0xF2F6EE; $0.eye = 0x0E2A20; $0.beak = true; $0.mouthDY = 3; $0.cheek = 0xFF7AA0
        $0.back = [birdWings(0x4AA88A, 0x2E7A64), featherTail(0x4AA88A, 0x2E7A64)]
        $0.muzzle = beak(0x3A3A3A, .needle)
        $0.feet = .talons(0x3A3A3A); $0.flies = true; $0.special = "sparkle"; $0.walkSpeed = 90
    },
    species("mellow", "Mellow", "lagoon", "animal", main: 0xA8B4BC, "A manatee calf that drifts wherever the current goes and greets everyone with a gentle bump.") {
        $0.body = .pebble; $0.rx = 9.2; $0.ry = 6.6; $0.belly = 0xD2DAE0; $0.eye = 0x1A2028; $0.mouthDY = 4; $0.feet = .none; $0.limb = 0x98A4AC
        $0.back = [lizardTail(0xA8B4BC, tip: .fluke(0x98A4AC), thick: 1.3, len: 0.6)]
        $0.muzzle = snout(0xD2DAE0, nose: 0x5A646C, w: 0.38)
        $0.top = [whiskers(0x6A747C)]
        $0.special = "bubbles"; $0.walkSpeed = 30; $0.sleepiness = 1.6
    },
    species("kiwibit", "Kiwibit", "bush", "animal", main: 0x9A7A58, "A round kiwi chick with no wings to speak of and a very long nose for finding worms.") {
        $0.rx = 7.4; $0.ry = 7; $0.eye = 0x1A1008; $0.beak = true; $0.mouthDY = 3; $0.fluffy = true; $0.noArms = true
        $0.muzzle = beak(0xD8C098, .needle)
        $0.feet = .talons(0xC8B090); $0.special = "seeds"; $0.walkSpeed = 60
    },
    species("possumkin", "Possumkin", "orchard", "animal", main: 0xC8C6CC, "An opossum joey that plays dead whenever it's surprised, then peeks to see if it worked.") {
        $0.rx = 7; $0.ry = 6.8; $0.eye = 0x14141A; $0.mouthDY = 4; $0.cheek = 0xFFA8B8
        $0.back = [roundEars(0x2E2E34, size: 0.85, spread: 0.6), thinTail(0xF2C0C4)]
        $0.surface = [facePatch(0xFAFAF8, w: 0.6, h: 0.5)]
        $0.muzzle = snout(0xFAFAF8, nose: 0xE88A9A, w: 0.24)
        $0.special = "sparkle"; $0.walkSpeed = 55
    },
    species("whistlet", "Whistlet", "alpine", "animal", main: 0xB08A60, "A marmot that whistles a warning for everything: hawks, clouds, falling leaves.") {
        $0.body = .pear; $0.rx = 7.6; $0.ry = 7.4; $0.belly = 0xE6CFA8; $0.eye = 0x1E140A; $0.mouthDY = 4; $0.teeth = true
        $0.back = [roundEars(0x8A6A48, size: 0.65, spread: 0.6), bushyTail(0x8A6A48, big: 0.7)]
        $0.muzzle = snout(0xE6CFA8, nose: 0x2A1A10, w: 0.28)
        $0.special = "notes"; $0.walkSpeed = 60
    },
]
