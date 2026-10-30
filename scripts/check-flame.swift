import AppKit

@main
struct FlameCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        func require(_ condition:Bool,_ message:String) throws {
            if !condition { throw NSError(domain:"EmberCat.FlameCheck",code:1,
                userInfo:[NSLocalizedDescriptionKey:message]) }
        }
        func bytes(_ image:CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }

        let suite = "EmberCat.FlameCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let settings = NotchFlameSettings(defaults:defaults)
        settings.set(width:1.4,height:1.6)
        let restored = NotchFlameSettings(defaults:defaults)
        try require(abs(restored.widthScale-1.4)<0.0001 && abs(restored.heightScale-1.6)<0.0001,
            "Width and height must survive a new settings instance")
        let profile = NotchDisplayProfile(model:"fixture",screenName:"Retina fixture",
            screenFrame:CGRect(x:1440,y:120,width:1728,height:1117),
            notchFrame:CGRect(x:2220,y:1205,width:168,height:32),scale:2,menuBarHeight:32)
        let sized = profile.geometry(settings:restored)
        try require(sized.notchWidth==168 && sized.notchHeight==32,"Preserve system notch size")
        try require(abs(sized.notch.midX-sized.size.width/2)<0.0001,"Keep actual notch centered")
        try require(abs(sized.flameWidth-235.2)<0.0001,"Apply width to the flame, not the notch")
        restored.reset()
        try require(settings.widthScale==1 && settings.heightScale==1,"Reset automatic sizing")
        settings.set(width:0.01,height:12)
        try require(settings.widthScale==0.6 && settings.heightScale==1.8,"Bound manual sizing")

        let external = NotchDisplayProfile(model:"fixture",screenName:"External fixture",
            screenFrame:CGRect(x:-1920,y:200,width:1920,height:1080),notchFrame:nil,
            scale:1,menuBarHeight:24)
        try require(external.anchorFrame.midX==external.screenFrame.midX,"Center external display effect")
        try require(external.anchorFrame.maxY==external.screenFrame.maxY,"Use active display coordinates")
        try require(external.anchorFrame.height==24,"Use system menu bar metrics")

        let renderer = try NotchFlameRenderer(resourceDirectory: URL(
            fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
        try require(renderer.sequence.frameCount==160 && renderer.sequence.license=="CC0-1.0",
            "Load the licensed source sequence")
        let geometry = NotchFlameGeometry(notchWidth:180,notchHeight:32)
        func channels(_ speed:Double) throws -> [Double] {
            let data = bytes(try renderer.image(geometry:geometry,time:3.75,speed:speed))
            var rgb = [0.0,0.0,0.0]
            for offset in stride(from:0,to:data.count,by:4) {
                rgb[0] += Double(data[offset+2]); rgb[1] += Double(data[offset+1]); rgb[2] += Double(data[offset])
            }
            return rgb
        }
        let red = try channels(3), gold = try channels(45), blue = try channels(180)
        try require(red[0]>red[2]*4,"Low speed should be red")
        try require(gold[1]/gold[0]>red[1]/red[0],"Medium speed should become gold")
        try require(blue[2]>blue[0]*1.4,"High speed should become blue-white")

        for (width,height) in [(0.6,0.5),(1.0,1.0),(1.5,1.8)] {
            let geometry = NotchFlameGeometry(notchWidth:204,notchHeight:32,
                widthScale:width,heightScale:height)
            let image = try renderer.image(geometry:geometry,time:2.1,speed:180)
            let data = bytes(image)
            try require(data[(32*image.width+image.width/2)*4+3]==0,"Do not paint inside physical notch")
            for x in 0..<image.width {
                try require(data[((image.height-1)*image.width+x)*4+3]==0,"Fade before lower edge")
            }
            for y in 0..<image.height {
                try require(data[(y*image.width)*4+3]==0,"Transparent left edge")
                try require(data[(y*image.width+image.width-1)*4+3]==0,"Transparent right edge")
            }
            let idle = bytes(try renderer.image(geometry:geometry,time:2.1,speed:180,active:false))
            try require(idle.allSatisfy { $0==0 },"No residual pixels when idle")
            for offset in stride(from:0,to:data.count,by:4) {
                try require(data[offset]<=data[offset+3] && data[offset+1]<=data[offset+3]
                    && data[offset+2]<=data[offset+3],"Premultiplied alpha on light desktops")
            }
        }
        let first = bytes(try renderer.image(geometry:geometry,time:1,speed:90))
        let second = bytes(try renderer.image(geometry:geometry,time:1.4,speed:90))
        let differences = zip(first,second).filter { $0 != $1 }.count
        try require(differences>1000,"Source flame sequence must animate")
        let stillA = bytes(try renderer.image(geometry:geometry,time:1,speed:90,reduceMotion:true))
        let stillB = bytes(try renderer.image(geometry:geometry,time:8,speed:90,reduceMotion:true))
        try require(stillA==stillB,"Reduced motion should be stable")
        var last:Float = 0
        for speed in stride(from:0.0,through:220.0,by:0.1) {
            let heat = NotchFlameGeometry.heat(for:speed)
            try require(heat>=last && heat-last<0.02,"Continuous monotonic heat mapping")
            last=heat
        }
        let report:[String:Any] = ["passed":true,
            "checks":["licensed source sequence","saved settings and reset","physical and external display geometry",
                "GPU red/gold/blue color range","transparent bounds at three sizes",
                "premultiplied alpha","idle transparency","animated source sequence","reduced motion",
                "continuous heat mapping"],
            "device":NotchDisplayProfile.current()?.summary ?? "unknown",
            "redRGB":red,"goldRGB":gold,"blueRGB":blue,"changedBytes":differences]
        if CommandLine.arguments.count>2 {
            let url=URL(fileURLWithPath:CommandLine.arguments[2])
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:url)
        }
        print("PASS: saved sizing, display geometry, GPU colors, alpha bounds, idle, motion and continuous heat")
    }
}
