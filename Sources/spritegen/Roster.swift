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
    // ---------------------------------------------------------------- Approved by Braydon (design reviews, 2026-11-05)
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
    species("inklet", "Inklet", "deep", "mythic", main: 0xD9A6E8, "A baby kraken that squirts a little ink when it gets startled.") {
        $0.rx = 7.8; $0.ry = 7.6; $0.eye = 0x2A0E30; $0.glossy = true; $0.noArms = true; $0.feet = .none; $0.cheek = 0xFF8FB8
        $0.surface = [spots(0xF2D6F8, [(-0.55, -0.45, 1.1), (0.5, -0.6, 0.8), (0.7, 0.0, 0.7)])]
        $0.front = [tentacles()]
        $0.special = "ink"; $0.walkSpeed = 50
    },
    species("leaflet", "Leaflet", "spring", "spirit", main: 0x8FCB6A, "The first leaf of spring, which hopped off its branch to have a look around.") {
        $0.rx = 6.5; $0.ry = 8; $0.eye = 0x1E2A12; $0.eyeStyle = .dot; $0.faceV = -0.15; $0.limb = 0x6FAF4A
        $0.bodyDraw = leafBody(0x8FCB6A)
        $0.special = "leaves"; $0.walkSpeed = 70
    },
    species("puffcap", "Puffcap", "forest floor", "spirit", main: 0xF6EBD6, "A mushroom spirit that puffs out a little cloud of golden spores when it laughs.") {
        $0.rx = 7; $0.ry = 7; $0.eye = 0x2A1E10; $0.eyeStyle = .dot; $0.faceV = 0.42; $0.eyeGap = 0.3; $0.limb = 0xE8DCC0
        $0.bodyDraw = mushroomBody(0xC98A4A, 0xFFF2DA, 0xF6EBD6)
        $0.special = "pollen"; $0.walkSpeed = 45
    },
    species("marimoss", "Marimoss", "lake", "spirit", main: 0x5FA858, "A moss ball from the bottom of a quiet lake. Floats up whenever it's happy, which is always.") {
        $0.rx = 7; $0.ry = 7; $0.eye = 0x14280F; $0.fluffy = true; $0.restEyes = .happy; $0.floats = true; $0.feet = .none; $0.noArms = true
        $0.special = "bubbles"; $0.walkSpeed = 40
    },
    species("loglet", "Loglet", "woodpile", "spirit", main: 0x7A5A3A, "A log from the woodpile that would rather be a friend than firewood. Still sprouting.") {
        $0.rx = 7.5; $0.ry = 7; $0.eye = 0x2A1A0A; $0.eyeStyle = .dot; $0.limb = 0x6A4A2A
        $0.bodyDraw = logBody(0x7A5A3A, 0xE8C894, 0x8FCB6A)
        $0.special = "leaves"; $0.walkSpeed = 45
    },
    species("turnipkin", "Turnipkin", "field", "spirit", main: 0xFAF6F0, "A turnip that pulled itself up out of the field one morning and never went back.") {
        $0.rx = 7; $0.ry = 7; $0.eye = 0x2A2030; $0.eyeStyle = .dot; $0.faceV = 0.2; $0.limb = 0xEAE2D8
        $0.bodyDraw = turnipBody(0xFAF6F0, 0xB07AC8, 0x6FAF4A)
        $0.special = "leaves"; $0.walkSpeed = 55
    },
    species("clovette", "Clovette", "luck", "spirit", main: 0x7CC46A, "A four-leaf clover spirit. Finding it is lucky; being found is its favourite game.") {
        $0.rx = 8; $0.ry = 8; $0.eye = 0x14280F; $0.eyeStyle = .dot; $0.floats = true; $0.feet = .none; $0.noArms = true
        $0.bodyDraw = cloverBody(0x7CC46A)
        $0.special = "sparkle"; $0.walkSpeed = 55
    },
    species("whirlseed", "Whirlseed", "autumn", "spirit", main: 0xC89A6A, "A maple seed that spins like a helicopter. Loves high places and dramatic exits.") {
        $0.rx = 5; $0.ry = 5; $0.eye = 0x2A1A0A; $0.eyeStyle = .dot; $0.noArms = true; $0.limb = 0xA87A4A
        $0.bodyDraw = samaraBody(0xC89A6A, 0xE8C894)
        $0.flies = true; $0.special = "leaves"; $0.walkSpeed = 60
    },
    species("sakurin", "Sakurin", "spring breeze", "spirit", main: 0xFFC2D6, "A cherry blossom that drifted off its tree and decided not to land just yet.") {
        $0.rx = 8; $0.ry = 8; $0.eye = 0x3A1A28; $0.eyeStyle = .dot; $0.floats = true; $0.feet = .none; $0.noArms = true
        $0.bodyDraw = blossomBody(0xFFC2D6, 0xFFE38A)
        $0.special = "petals"; $0.walkSpeed = 50
    },
    species("puffcloud", "Puffcloud", "sky", "spirit", main: 0xF6F8FF, "A little cloud that came down to see what everyone was doing. Drizzles when it's moved.") {
        $0.body = .cloud; $0.rx = 9; $0.ry = 6.5; $0.eye = 0x2B3157; $0.eyeStyle = .dot; $0.floats = true; $0.feet = .none; $0.noArms = true; $0.cheek = 0xB9C8FF
        $0.flies = true; $0.special = "rain"; $0.walkSpeed = 45
    },
    species("rainlet", "Rainlet", "rain", "spirit", main: 0x7EC4F0, "The first raindrop of a storm, very proud of having arrived first.") {
        $0.rx = 6.5; $0.ry = 7; $0.eye = 0x14283A; $0.eyeStyle = .dot; $0.glossy = true; $0.limb = 0x5AA8E0
        $0.bodyDraw = dropBody(0x7EC4F0)
        $0.special = "rain"; $0.walkSpeed = 65; $0.jumpPower = 1.25
    },
    species("bubbit", "Bubbit", "soap", "spirit", main: 0xF2F8FF, "A soap bubble that refused to pop. It's very careful around anything pointy.") {
        $0.rx = 7; $0.ry = 7; $0.eye = 0x2A3050; $0.eyeStyle = .dot; $0.floats = true; $0.feet = .none; $0.noArms = true
        $0.bodyDraw = bubbleBody()
        $0.flies = true; $0.special = "bubbles"; $0.walkSpeed = 40
    },
    species("glowmote", "Glowmote", "light", "spirit", main: 0xFFF6DC, "A mote of evening light that forgot to go home with the sunset.") {
        $0.rx = 5.6; $0.ry = 5.6; $0.eye = 0x5A4A20; $0.eyeStyle = .dot; $0.floats = true; $0.feet = .none; $0.noArms = true; $0.cheek = 0xFFC8A0
        $0.bodyDraw = lightBody(0xFFF6DC, 0xFFE08A)
        $0.flies = true; $0.special = "glow"; $0.walkSpeed = 55
    },
    species("pebblin", "Pebblin", "earth", "spirit", main: 0xB8B4AC, "A stack of river stones that balanced itself one day and has been very careful ever since.") {
        $0.rx = 8; $0.ry = 8; $0.eye = 0x2A2620; $0.eyeStyle = .dot; $0.faceV = -0.62; $0.eyeGap = 0.3; $0.feet = .none; $0.noArms = true; $0.cheeks = false
        $0.bodyDraw = cairnBody(0xB8B4AC, 0xA4AEB4, 0x7CC46A)
        $0.special = "sparkle"; $0.walkSpeed = 35; $0.jumpPower = 0.8
    },

    // ---------------------------------------------------------------- Guardians: old machines that nature reclaimed
    species("mosswarden", "Mosswarden", "patina", "guardian", main: 0x8FBFB0, "An old guardian machine that stood watch so long a meadow grew on its head. It guards the flowers now.") {
        $0.rx = 7.5; $0.ry = 7; $0.eye = 0x2A6A8A; $0.eyeStyle = .cyclops; $0.faceV = 0.05; $0.limb = 0x6E9A8E; $0.restMouth = Mouth.none
        $0.bodyDraw = cogwardenBody(0x8FBFB0, 0x7CC46A, 0xFF9EC4)
        $0.special = "petals"; $0.walkSpeed = 40; $0.jumpPower = 0.8
    },
    species("sproutbolt", "Sproutbolt", "enamel", "guardian", main: 0xEDE6D6, "A little machine whose antenna fell off. A sapling grew in the socket and it's been gardening ever since.") {
        $0.rx = 6.5; $0.ry = 6.5; $0.eye = 0x1A3A4A; $0.eyeStyle = .glow(0x7FD8FF); $0.limb = 0xC8BFAE; $0.restMouth = Mouth.none
        $0.bodyDraw = rivetBody(0xEDE6D6, 0xC8D8E0, 0x7CC46A)
        $0.special = "leaves"; $0.walkSpeed = 60
    },
    species("orbwarden", "Orbwarden", "sky patrol", "guardian", main: 0xC8D2DA, "A round patrol drone that drifts the same slow loop every day, trailing the vines that grew on it.") {
        $0.rx = 6.2; $0.ry = 6.2; $0.eye = 0x2A6A8A; $0.eyeStyle = .cyclops; $0.floats = true; $0.feet = .none; $0.noArms = true; $0.restMouth = Mouth.none
        $0.bodyDraw = orbDroneBody(0xC8D2DA, 0xE8A85A, 0x6FAF4A)
        $0.flies = true; $0.special = "sparkle"; $0.walkSpeed = 50
    },
    species("trundle", "Trundle", "rust", "guardian", main: 0xD9A27A, "A tread-wheeled machine with a mushroom growing on its head. It drives very carefully so the mushroom doesn't fall.") {
        $0.rx = 7; $0.ry = 6.5; $0.eye = 0x3A2A10; $0.eyeStyle = .glow(0xFFE08A); $0.feet = .none; $0.limb = 0xB88460; $0.restMouth = Mouth.none
        $0.bodyDraw = treadBody(0xD9A27A, 0x5A5A62, 0xC98A4A)
        $0.special = "stomp"; $0.walkSpeed = 55
    },
    species("boilerbit", "Boilerbit", "steam", "guardian", main: 0xE0B866, "A brass boiler machine that puffs a little steam whenever it's thinking hard.") {
        $0.rx = 6.8; $0.ry = 7; $0.eye = 0x1A3A4A; $0.eyeStyle = .glow(0x7FD8FF); $0.faceV = -0.35; $0.limb = 0xA8763A; $0.restMouth = Mouth.none
        $0.bodyDraw = boilerBody(0xE0B866, 0xA8763A)
        $0.special = "steam"; $0.walkSpeed = 45
    },
    species("listenling", "Listenling", "signal", "guardian", main: 0xB8C8D0, "A machine with a listening dish on its head. It was built to hear far-off signals; now it mostly listens to birdsong.") {
        $0.rx = 6.8; $0.ry = 6.5; $0.eye = 0x1A3A2A; $0.eyeStyle = .glow(0x9AF0B0); $0.limb = 0x9AAAB2; $0.restMouth = Mouth.none
        $0.bodyDraw = dishBody(0xB8C8D0, 0x7CC46A)
        $0.special = "notes"; $0.walkSpeed = 50
    },
    species("bloomcore", "Bloomcore", "blossom", "guardian", main: 0xA8B8C8, "Its chest panel fell open years ago and a flower grew where its core used to be.") {
        $0.rx = 7; $0.ry = 7; $0.eye = 0x3A1A2A; $0.eyeStyle = .glow(0xFFB0D0); $0.faceV = -0.45; $0.limb = 0x8A9AAA; $0.restMouth = Mouth.none
        $0.bodyDraw = bloomChestBody(0xA8B8C8, 0xFF9EC4, 0x6FAF4A)
        $0.special = "petals"; $0.walkSpeed = 45
    },
    species("slumberbolt", "Slumberbolt", "dormant", "guardian", main: 0x9AA8B0, "An armoured machine that curled up for a nap a century ago. Moss thinks it's a rock.") {
        $0.rx = 8.5; $0.ry = 6.2; $0.eye = 0x1A3A2A; $0.eyeStyle = .glow(0x9AF0B0); $0.restEyes = .sleepy; $0.faceV = 0.3; $0.noArms = true; $0.limb = 0x7A8890; $0.restMouth = Mouth.none
        $0.bodyDraw = shellBotBody(0x9AA8B0, 0x7CC46A)
        $0.special = "sparkle"; $0.walkSpeed = 30; $0.sleepiness = 2.0
    },
    species("rotorlet", "Rotorlet", "breeze", "guardian", main: 0xF2D6A0, "A tiny scout machine with a rotor on its head. Hovers just high enough to see over the grass.") {
        $0.rx = 5.6; $0.ry = 5.6; $0.eye = 0x1A3A4A; $0.eyeStyle = .glow(0x7FD8FF); $0.limb = 0xD2B680; $0.restMouth = Mouth.none
        $0.bodyDraw = rotorBody(0xF2D6A0, 0xD8E8F0)
        $0.flies = true; $0.special = "leaves"; $0.walkSpeed = 70
    },
    species("stridelet", "Stridelet", "outpost", "guardian", main: 0xE8EEF2, "A round lookout machine on springy legs. It tiptoes around sleeping animals.") {
        $0.rx = 6.2; $0.ry = 6.2; $0.eye = 0x2A6A8A; $0.eyeStyle = .cyclops; $0.feet = .none; $0.noArms = true; $0.faceV = -0.85; $0.restMouth = Mouth.none
        $0.bodyDraw = walkerBody(0xE8EEF2, 0x8A96A2)
        $0.special = "sparkle"; $0.walkSpeed = 75; $0.jumpPower = 1.4
    },

    // ---------------------------------------------------------------- Motes
    species("pondhead", "Pondhead", "rainwater", "guardian", main: 0xB8C4B0, "A squat old machine with a dent in its head that filled with rain. A lily pad and a little flower live there now.") {
        $0.rx = 8.5; $0.ry = 6.2; $0.eye = 0x1A3A2A; $0.eyeStyle = .glow(0x9AF0B0); $0.limb = 0x96A290; $0.restMouth = Mouth.none; $0.faceV = 0.05
        $0.bodyDraw = pondHeadBody(0xB8C4B0, 0x8FD3F0, 0x7CC46A)
        $0.special = "bubbles"; $0.walkSpeed = 35; $0.jumpPower = 0.75
    },
    species("ivybolt", "Ivybolt", "overgrowth", "guardian", main: 0xD8CFC0, "A tall machine so wrapped in ivy that only its eyes peek out. It moves slowly so the leaves don't fall.") {
        $0.rx = 6.2; $0.ry = 8.2; $0.eye = 0x1A3A2A; $0.eyeStyle = .glow(0xFFE08A); $0.faceV = -0.5; $0.limb = 0xB8AE9E; $0.restMouth = Mouth.none
        $0.bodyDraw = ivyBody(0xD8CFC0, 0x6FAF4A)
        $0.special = "leaves"; $0.walkSpeed = 35
    },
    species("beaconbit", "Beaconbit", "lighthouse", "guardian", main: 0xE8E2D4, "A little machine with a beacon on its head. It lights the way home for anything lost after dark.") {
        $0.rx = 6.4; $0.ry = 6.2; $0.eye = 0x1A3A4A; $0.eyeStyle = .glow(0x7FD8FF); $0.limb = 0xC8C0AE; $0.restMouth = Mouth.none
        $0.bodyDraw = beaconBody(0xE8E2D4, 0xBFE4F2, 0xFFE08A)
        $0.special = "glow"; $0.walkSpeed = 55
    },
    species("emberglow", "Emberglow", "ember", "spirit", main: 0xFFD0A0, "The last warm glow from a campfire, still wandering around after everyone went to bed.") {
        $0.rx = 5.6; $0.ry = 5.6; $0.eye = 0x5A2A10; $0.eyeStyle = .dot; $0.floats = true; $0.feet = .none; $0.noArms = true; $0.cheek = 0xFF9A7A
        $0.bodyDraw = lightBody(0xFFD0A0, 0xFF9A5A)
        $0.flies = true; $0.special = "glow"; $0.walkSpeed = 55
    },
    species("frostmote", "Frostmote", "frost", "spirit", main: 0xEAF6FF, "A mote of winter light that paints frost on windows when nobody is looking.") {
        $0.rx = 5.6; $0.ry = 5.6; $0.eye = 0x1A2A4A; $0.eyeStyle = .dot; $0.floats = true; $0.feet = .none; $0.noArms = true; $0.cheek = 0xB8D0FF
        $0.bodyDraw = lightBody(0xEAF6FF, 0xA8D8FF)
        $0.flies = true; $0.special = "snow"; $0.walkSpeed = 55
    },
]
