import Foundation

enum MatrixFlowPass: String, CaseIterable {
    case composed, background, falling, gathering, orbiting, aperture
}

struct MatrixPulseVertex {
    var positionAndUV: SIMD4<Float>
    var material: SIMD4<Float>
}

struct MatrixPulseSample: Equatable {
    let id: UInt64
    let center: SIMD2<Float>
    let width: Float
    let clockRate: Float
    let opacity: Float
    let stage: MatrixFlowPass
    let codeSeed: Float
    let brightness: Float
}

struct MatrixPulse: Equatable {
    let id: UInt64
    let depth: Float
    let opacity: Float
    let sourceX: Float
    let bundle: Int
    let samples: [MatrixPulseSample]

    var vertices: [MatrixPulseVertex] {
        var result: [MatrixPulseVertex] = []
        result.reserveCapacity(samples.count*6)
        for sample in samples where sample.opacity > 0.0001 {
            let clock = sample.stage == .background ? -sample.clockRate : sample.clockRate
            let material = SIMD4(opacity*sample.opacity,sample.brightness,clock,sample.codeSeed)
            // Each character keeps its own identity from the wall to its final inward orbit.
            let halfWidth = sample.width*0.68,halfHeight = sample.width*0.76
            func vertex(_ x: Float,_ y: Float,_ u: Float,_ v: Float) -> MatrixPulseVertex {
                MatrixPulseVertex(positionAndUV: SIMD4(sample.center.x+x,sample.center.y+y,v,u),
                    material:material)
            }
            let topLeft = vertex(-halfWidth,-halfHeight,-1.4,-0.08)
            let topRight = vertex(halfWidth,-halfHeight,1.4,-0.08)
            let bottomLeft = vertex(-halfWidth,halfHeight,-1.4,1.08)
            let bottomRight = vertex(halfWidth,halfHeight,1.4,1.08)
            result += [topLeft,topRight,bottomLeft,topRight,bottomRight,bottomLeft]
        }
        return result
    }
}

struct MatrixPortPulse: Equatable {
    let x: Float
    let intensity: Float
    let radius: Float
    var uniform: SIMD4<Float> { SIMD4(x,intensity,radius,0) }
}

struct MatrixFlowFrame {
    var pulses: [MatrixPulse] = []
    var ports: [MatrixPortPulse] = []
    var vertices: [MatrixPulseVertex] {
        var background: [MatrixPulseVertex] = [],foreground: [MatrixPulseVertex] = []
        for pulse in pulses {
            for vertex in pulse.vertices {
                if vertex.material.z < 0 { background.append(vertex) }
                else { foreground.append(vertex) }
            }
        }
        return background+foreground
    }
}

/// Vertical rain feeds a movable central sink, with residue confined to its opening.
/// The gravity field is an artistic motion model, not a physical simulation.
enum MatrixCodeFlow {
    static let sessionSeed = UInt64.random(in: UInt64.min...UInt64.max)
    static let previewSeed: UInt64 = 0xA91F_47C2_D503_6B8E
    static let sourceColumns = 32
    static let gatheringBundles = 4
    static let maximumPulses = sourceColumns
    static let maximumPorts = maximumPulses
    static let pulseSegments = 384
    static let maximumVertices = maximumPulses*pulseSegments*6
    static let maximumInlineVertices = 120
    private static let emissionOrder = [0,31,15,16] + (0..<sourceColumns)
        .map { ($0*13)%sourceColumns }.filter { ![0,31,15,16].contains($0) }

    static func horizon(geometry: NotchFlameGeometry,
                        configuration: NotchMatrixConfiguration = .standard) -> SIMD4<Float> {
        let size = configuration.validationError == nil ? configuration.blackHoleSize : NotchMatrixConfiguration.standard.blackHoleSize
        let radius = Float(min(15.5,max(10.5,geometry.notchWidth*0.075))*size)
        let offset = configuration.validationError == nil ? configuration.verticalOffset : 0
        return SIMD4(Float(geometry.notch.midX),Float(geometry.notchHeight)+Float(offset),radius,1)
    }

    static func diskPlane(geometry: NotchFlameGeometry,
                          configuration: NotchMatrixConfiguration = .standard) -> SIMD4<Float> {
        let hole = horizon(geometry: geometry,configuration:configuration)
        return SIMD4(hole.x,hole.y+hole.z*0.05,0.82,0.025)
    }

    static func diskPoint(_ point: SIMD2<Float>,geometry: NotchFlameGeometry,
                          configuration: NotchMatrixConfiguration = .standard) -> SIMD2<Float> {
        let plane = diskPlane(geometry: geometry,configuration:configuration)
        let x = point.x-plane.x
        return SIMD2(x,(point.y-plane.y-x*plane.w)/plane.z)
    }

    static func localClockRate(distance: Double,radius: Double) -> Double {
        0.22+0.78*smooth(radius+3,radius+34,distance)
    }

    static func motionMultiplier(heat: Double) -> Double {
        guard heat.isFinite else { return 0.55 }
        return 0.55+0.80*min(1,max(0,heat))
    }

    static func frame(geometry: NotchFlameGeometry,time: Double,heat: Float,
                      configuration: NotchMatrixConfiguration = .standard,
                      pass: MatrixFlowPass = .composed,
                      seed: UInt64 = previewSeed) -> MatrixFlowFrame {
        let width = Double(geometry.notchWidth)
        guard pass != .aperture,heat.isFinite,heat > 0,time.isFinite,width.isFinite,width > 0,
              geometry.notchHeight.isFinite,configuration.validationError == nil else { return MatrixFlowFrame() }
        let fit = min(1.12,width/180)
        let budget = 4+Double(maximumPulses-4)*pow(Double(min(1,heat)),0.92)
        var result = MatrixFlowFrame()
        for slot in 0..<maximumPulses {
            let loadOpacity = smooth(Double(slot),Double(slot+1),budget)
            guard loadOpacity > 0.0001 else { continue }
            // Keep both rounded ends and the two mouth columns present at every load.
            let column = emissionOrder[slot]
            let lane = mix(seed &+ UInt64(column) &* 0xD1B5_4A32_D192_ED03)
            let direct = makePath(geometry:geometry,configuration:configuration,column:column,seed:lane,lingering:false)
            let lingering = makePath(geometry:geometry,configuration:configuration,column:column,seed:lane,lingering:true)
            let background = makeBackgroundPath(geometry:geometry,column:column,seed:lane)
            let gap = 0.22+random(lane,12)*0.04
            let clock = max(0,time)+random(lane,15)*71
            let newest = floor(clock/(gap*0.25))+2
            let depth = Float(0.35+random(lane,16)*0.65)
            let baseWidth = (3.40+Double(depth)*0.35)*fit
            var samples: [MatrixPulseSample] = []
            let recentCount = min(pulseSegments,
                Int(ceil((max(direct.duration,lingering.duration,background.duration)+gap)/(gap*0.25)))+3)
            for index in 0..<recentCount {
                let emission = newest-Double(index)
                let generation = floor(emission/4)
                let slot = Int(emission-generation*4)
                // Preserve the original 100%/200% birth times and identities. The
                // extra quarter-step band makes 200–300% genuinely add characters.
                let band = [0,2,1,3][slot]
                guard band < 3 else { continue }
                let salt: UInt64 = band == 0 ? 0 : band == 1 ? 0xA2E9_6D53_4B78_1C0F : 0x7C13_98B4_E6A5_D20F
                let event = mix(lane ^ generation.bitPattern ^ salt)
                // A fixed interleaved birth grid lets density reveal extra characters
                // without moving or replacing any character already on screen.
                let rank = random(event,31)*0.92
                let density = smooth(rank,rank+0.08,configuration.density-Double(band))
                guard density > 0.0001 else { continue }
                let age = clock-emission*gap*0.25-(random(event,18)-0.5)*gap*0.60
                // Reassign part of the existing rain; do not add another full-density wall.
                let ambient = random(event,33) < 0.30
                let path = ambient ? background : random(event,17) < 0.12 ? lingering : direct
                guard age >= 0,age < path.duration else { continue }
                let point = path.at(clock:age)
                let orbital = point.stage == .orbiting
                let widthScale = ambient ? 0.76 : orbital ? 0.74 : point.stage == .gathering ? 0.88 : 1
                let width = baseWidth*widthScale*(0.87+0.13*point.rate)
                // Captured characters retire inside the shadow. Background rain passes
                // behind it and fades lower down, without responding to the gravity field.
                let life = smooth(0,0.12,age)*(ambient ? 1-smooth(path.duration-1,path.duration-0.05,age) : 1)
                let selected = pass == .composed || pass == point.stage
                let disk = diskPoint(SIMD2(Float(point.position.x),Float(point.position.y)),
                    geometry:geometry,configuration:configuration)
                let angle = atan2(Double(disk.y),Double(disk.x))
                // Broad, slowly advected density pockets break the outline of complete glyph rings.
                let pocket = 0.30+0.70*pow(0.5+0.5*sin(angle*2-time*0.52+Double(column%3)*0.32),2)
                let opacity = ambient ? 0.24 : orbital ? 0.68*pocket : point.stage == .gathering ? 0.72 : 1
                samples.append(MatrixPulseSample(id:event,
                    center:SIMD2(Float(point.position.x),Float(point.position.y)),
                    width:Float(width),clockRate:Float(point.rate),
                    opacity:Float(selected ? life*opacity*density : 0),stage:point.stage,
                    codeSeed:Float(floor(random(event,24)*4096)),
                    brightness:Float(0.58+0.42*pow(random(event,25),1.5))))
            }
            guard samples.contains(where: { $0.opacity > 0.0001 }) else { continue }
            result.pulses.append(MatrixPulse(id:lane,depth:depth,
                opacity:Float(loadOpacity)*(0.57+depth*0.40),
                sourceX:Float(direct.points[0].position.x),bundle:column/8,samples:samples))
        }
        result.pulses.sort { $0.depth == $1.depth ? $0.id < $1.id : $0.depth < $1.depth }
        result.ports = result.pulses.compactMap { pulse in
            guard let contact = pulse.samples.filter({ $0.opacity > 0.01 && $0.stage != .background }).min(by: {
                abs($0.center.y-Float(geometry.notchHeight)) < abs($1.center.y-Float(geometry.notchHeight))
            }) else { return nil }
            let strength = exp(-pow((Double(contact.center.y)-Double(geometry.notchHeight))/2.5,2))
                * Double(pulse.opacity*contact.opacity)
            guard strength > 0.02 else { return nil }
            return MatrixPortPulse(x:contact.center.x,intensity:Float(min(1,strength)),radius:2.6)
        }
        return result
    }

    private struct FlowPoint {
        var position: SIMD2<Double>
        var rate: Double
        var speed: Double
        var stage: MatrixFlowPass
    }

    private struct ClockPath {
        let points: [FlowPoint]
        let clocks: [Double]
        let duration: Double

        init(points:[FlowPoint]) {
            self.points = points
            var clocks = [0.0]
            for index in 1..<points.count {
                let a = points[index-1],b = points[index]
                let speed = (a.speed+b.speed)*0.5
                clocks.append(clocks.last!+length(b.position-a.position)/speed)
            }
            self.clocks = clocks
            duration = clocks.last!
        }

        func at(clock:Double) -> FlowPoint {
            if clock <= 0 { return points[0] }
            if clock >= duration { return points.last! }
            var lower = 0,upper = clocks.count-1
            while upper-lower > 1 {
                let middle = (lower+upper)/2
                if clocks[middle] < clock { lower = middle } else { upper = middle }
            }
            let fraction = (clock-clocks[lower])/max(0.0001,clocks[upper]-clocks[lower])
            let a = points[lower],b = points[upper]
            return FlowPoint(position:a.position+(b.position-a.position)*fraction,
                rate:a.rate+(b.rate-a.rate)*fraction,speed:a.speed+(b.speed-a.speed)*fraction,
                stage:b.stage)
        }
    }

    private static func makeBackgroundPath(geometry:NotchFlameGeometry,column:Int,seed:UInt64) -> ClockPath {
        let fit = min(1.12,Double(geometry.notchWidth)/180)
        let halfWidth = Double(geometry.notchWidth)*0.5
        let x = -halfWidth+1.25*fit+(Double(geometry.notchWidth)-2.5*fit)*Double(column)/Double(sourceColumns-1)
        let corner = Double(geometry.cornerRadius)
        let cornerX = max(0,abs(x)-(halfWidth-corner))
        let edgeY = Double(geometry.notchHeight)-corner+sqrt(max(0,corner*corner-cornerX*cornerX))
        let source = SIMD2(Double(geometry.notch.midX)+x,edgeY-0.25)
        let speed = (18+6*random(seed,34))*fit
        return ClockPath(points:[
            FlowPoint(position:source,rate:1,speed:speed,stage:.background),
            FlowPoint(position:source+SIMD2(0,82*fit),rate:1,speed:speed,stage:.background)
        ])
    }

    private static func makePath(geometry:NotchFlameGeometry,configuration:NotchMatrixConfiguration,
                                 column:Int,seed:UInt64,lingering:Bool) -> ClockPath {
        let hole = horizon(geometry:geometry,configuration:configuration)
        let plane = diskPlane(geometry:geometry,configuration:configuration)
        let radius = Double(hole.z),fit = min(1.12,Double(geometry.notchWidth)/180)
        let cx = Double(hole.x),cy = Double(hole.y),edge = Double(geometry.notchHeight)
        let halfWidth = Double(geometry.notchWidth)*0.5
        let outerRadius = halfWidth-1.25*fit
        // Only the actual intersection blocks the wall. Detached holes receive rain
        // from the middle of the notch too, rather than leaving a phantom source gap.
        let mouth = sqrt(max(0,radius*radius-configuration.verticalOffset*configuration.verticalOffset))
        let inner = mouth > 0 ? mouth+1.4*fit : 0
        let side = column < sourceColumns/2 ? -1.0 : 1.0
        let sideIndex = column < sourceColumns/2 ? 15-column : column-16
        let lane = (Double(sideIndex)+0.5)/15.5
        let sourceRadius = inner+(outerRadius-inner)*lane+(random(seed,0)-0.5)*0.60*fit*(1-lane)
        let corner = Double(geometry.cornerRadius)
        let cornerX = max(0,sourceRadius-(halfWidth-corner))
        let sourceEdge = edge-corner+sqrt(max(0,corner*corner-cornerX*cornerX))
        let source = SIMD2(cx+side*sourceRadius,sourceEdge-0.25)
        let gravity = sqrt(configuration.gravity)
        let proximity = 1-smooth(radius*1.25,radius*4.6,sourceRadius)
        let group = column/8
        let outer = group == 0 || group == 3
        let bundleRadius = inner+(outerRadius-inner)*(outer ? 0.77 : 0.25)
        let rimAngle = outer ? 0.66 : 0.32
        // One orbital direction needs opposite depth at the two inlets: left
        // enters behind the shadow, right enters in front. Mirroring both onto
        // the near side makes the left approach hook outward to meet its tangent.
        let embeddedAngle = side < 0 ? Double.pi+0.02 : rimAngle
        var incomingAngle = atan2(edge-cy,side*bundleRadius)
        if side < 0 && incomingAngle < 0 { incomingAngle += Double.pi*2 }
        let detached = smooth(radius*0.3,radius*1.6,configuration.verticalOffset)
        let angleJitter = (random(seed,1)-0.5)*(side < 0 ? 0.01 : 0.055)
        let angle = embeddedAngle+(incomingAngle-embeddedAngle)*detached+angleJitter
        // The rear inlet crosses the side of the physical shadow before turning
        // upward behind it, keeping the approach below the notch until capture.
        let orbitRadius = radius*(side < 0 || lingering ? 0.98 : 1.03+0.035*random(seed,2))
        func project(_ r:Double,_ theta:Double) -> SIMD2<Double> {
            let x = cos(theta)*r,y = sin(theta)*r
            return SIMD2(cx+x,Double(plane.y)+y*Double(plane.z)+x*Double(plane.w))
        }
        let entry = project(orbitRadius,angle)
        var orbitTangent = SIMD2(-sin(angle),cos(angle)*Double(plane.z)-sin(angle)*Double(plane.w))
        orbitTangent /= max(0.001,length(orbitTangent))
        let clearance = max(0,cy-radius-source.y)
        var fallDistance = (4+30*(1-proximity))*fit/gravity+clearance*0.70
        if sourceRadius < radius {
            let topOfHole = cy-sqrt(radius*radius-sourceRadius*sourceRadius)
            fallDistance = min(fallDistance,max(0.5,topOfHole-source.y-1.4*fit))
        }
        let fallEnd = source+SIMD2(0,fallDistance)
        let reach = length(entry-fallEnd)
        let firstControl = fallEnd+SIMD2(0,min(14*fit,max(2*fit,reach*0.30)))
        let secondControl = entry-orbitTangent*min(radius*0.16,reach*0.14)
        var points: [FlowPoint] = []
        func add(_ p:SIMD2<Double>,stage:MatrixFlowPass,orbitalRadius:Double? = nil,
                 acceleration:Double = 0,arrival:Double = 0) {
            let distance = orbitalRadius ?? length(p-SIMD2(cx,Double(hole.y)))
            let rate = localClockRate(distance:distance,radius:radius)
            let fallingSpeed = 24+10*rate,gatheringSpeed = (58+34*rate)*gravity
            let orbitSpeed = 22*(0.30+0.70*rate)
            let speed = orbitalRadius != nil ? orbitSpeed
                : (fallingSpeed+(gatheringSpeed-fallingSpeed)*acceleration)*(1-arrival)+orbitSpeed*arrival
            points.append(FlowPoint(position:p,rate:rate,speed:speed,stage:stage))
        }
        // Upright columns remain genuinely vertical before entering the attraction
        // curve. They never become independent sideways swimmers or a broad disk.
        for index in 0...24 {
            let t = Double(index)/24
            add(source+(fallEnd-source)*t,stage:.falling)
        }
        for index in 1...64 {
            let t = Double(index)/64
            add(bezier(fallEnd,firstControl,secondControl,entry,t),stage:.gathering,
                acceleration:smooth(0,0.55,t),arrival:smooth(0.50,1,t))
        }
        // Residue belongs to the mouth and drains locally; no wide lateral orbit.
        let turns = lingering ? (outer ? 0.65 : 0.78) : 0.22
        for index in 1...192 {
            let t = Double(index)/192
            let drain = smooth(lingering ? 0.10+random(seed,3)*0.10 : 0,1,t)
            // The projected disk center is inside the shadow. Drain all the way there;
            // stopping on an inner disk ellipse can leave foreground code outside the hole.
            let r = orbitRadius*(1-drain)
            add(project(r,angle+Double.pi*2*turns*t),stage:.orbiting,orbitalRadius:r)
        }
        return ClockPath(points:points)
    }

    private static func bezier(_ a:SIMD2<Double>,_ b:SIMD2<Double>,_ c:SIMD2<Double>,
                               _ d:SIMD2<Double>,_ t:Double) -> SIMD2<Double> {
        let u = 1-t
        return a*(u*u*u)+b*(3*u*u*t)+c*(3*u*t*t)+d*(t*t*t)
    }

    private static func length(_ vector:SIMD2<Double>) -> Double {
        sqrt(vector.x*vector.x+vector.y*vector.y)
    }

    private static func mix(_ value:UInt64) -> UInt64 {
        var value = value &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private static func random(_ seed:UInt64,_ index:UInt64) -> Double {
        Double(mix(seed &+ index &* 0xD1B5_4A32_D192_ED03) >> 11)/9_007_199_254_740_992.0
    }

    private static func smooth(_ lower:Double,_ upper:Double,_ value:Double) -> Double {
        let x = min(1,max(0,(value-lower)/(upper-lower)))
        return x*x*(3-2*x)
    }
}
