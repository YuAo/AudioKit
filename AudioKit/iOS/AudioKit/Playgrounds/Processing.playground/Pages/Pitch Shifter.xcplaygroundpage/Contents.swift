//: [TOC](Table%20Of%20Contents) | [Previous](@previous) | [Next](@next)
//:
//: ---
//:
//: ## Time Stretching and Pitch Shifting
//: ### With AKTimePitch you can easily change the pitch and speed of a
//: ### player-generated sound.  It does not work on live input or generated signals.
//:
import XCPlayground
import AudioKit

let file = try AKAudioFile(readFileName: AKPlaygroundView.audioResourceFileNames[0],
                           baseDir: .Resources)
var player = try AKAudioPlayer(file: file)
player.looping = true

var pitchshifter = AKPitchShifter(player)

AudioKit.output = pitchshifter
AudioKit.start()
player.play()

//: User Interface Set up

class PlaygroundView: AKPlaygroundView {

    override func setup() {
        addTitle("Pitch Shifter")

        addSubview(AKResourcesAudioFileLoaderView(
            player: player,
            filenames: AKPlaygroundView.audioResourceFileNames))

        addSubview(AKBypassButton(node: pitchshifter))

        addSubview(AKPropertySlider(
            property: "Pitch",
            format: "%0.3f Semitones",
            value: pitchshifter.shift, minimum: -24, maximum: 24,
            color: AKColor.greenColor()
        ) { sliderValue in
            pitchshifter.shift = sliderValue
            })
    }
}

let view = PlaygroundView(frame: CGRect(x: 0, y: 0, width: 500, height: 600))
XCPlaygroundPage.currentPage.needsIndefiniteExecution = true
XCPlaygroundPage.currentPage.liveView = view

//: [TOC](Table%20Of%20Contents) | [Previous](@previous) | [Next](@next)
