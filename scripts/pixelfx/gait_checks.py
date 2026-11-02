"""Geometric checks on exported poses, independent of the pose generator."""
import math


def check_pose(row,measurements):
    joints=row['joints'];largest_error=0
    for point in joints.values():assert all(math.isfinite(v) for v in point)
    for side,key in [('N','near'),('F','far')]:
        for a,b,length in [('hip','knee','thigh'),('knee','ankle','shin'),
                           ('shoulder','elbow','upper'),('elbow','hand','fore')]:
            largest_error=max(largest_error,abs(math.dist(joints[a+side],joints[b+side])-measurements[length]))
        hip,knee,ankle=[joints[name+side] for name in ['hip','knee','ankle']]
        bend=(knee[0]-hip[0])*(ankle[1]-knee[1])-(knee[1]-hip[1])*(ankle[0]-knee[0])
        assert bend<0,(row['mode'],row['phase'],side,'knee reversed')
        f=row[key];a=math.radians(f['pitch'])
        contact_y=ankle[1]-f['pivot']*math.sin(a)-f['soleHeight']*math.cos(a)
        assert abs(contact_y-f['lift'])<1e-8,(row['mode'],'sole leaves its contact plane')
        assert abs(ankle[0]-f['x'])<1e-8
    assert largest_error<1e-8,('bone stretch',largest_error)
    return largest_error


def support_slip(poses,key,side,velocity):
    positions=[]
    for row in poses:
        f=row[key]
        if not f['support']:continue
        ankle=row['joints']['ankle'+side];a=math.radians(f['pitch'])
        # Recover the planted sole from the actual skeleton and shoe rotation.
        x=ankle[0]+f['pivot']*math.cos(a)-f['soleHeight']*math.sin(a)-f['pivot']
        positions.append(x+velocity*f['phase'])
    assert positions
    error=max(positions)-min(positions)
    assert error<1e-8,('planted sole slides',side,error)
    return error


def check_board(poses):
    assert max(math.dist(r['joints']['ankleF'],poses[0]['joints']['ankleF']) for r in poses)<1e-8
    assert all(r['far']['onDeck'] and abs(r['far']['lift']-2.2)<1e-8 for r in poses)
    pushing=[r for r in poses if r['near']['support']]
    gliding=[r for r in poses if r['near']['onDeck']]
    assert len(pushing)>25 and len(gliding)>30,'missing push or sustained two-foot glide'
    assert all(abs(r['near']['lift'])<1e-8 for r in pushing)
    assert all(abs(r['near']['lift']-2.2)<1e-8 for r in gliding)
    assert max(r['near']['lift'] for r in poses)>3.6,'recovery does not clear the deck'
    assert max(math.dist(r['joints']['ankleN'],gliding[0]['joints']['ankleN']) for r in gliding)<1e-8
    support_slip(pushing,'near','N',27.5)


def check_skates(poses):
    assert all(r['near']['support'] or r['far']['support'] for r in poses),'both skates airborne'
    for key in ['near','far']:
        assert min(r[key]['groundX'] for r in poses)<-6.5,'no rearward push'
        assert max(r[key]['lift'] for r in poses)>3.2,'no skate recovery'
        for row in poses:
            f=row[key]
            if f['support']:assert abs(f['lift'])<1e-8 and abs(f['pitch'])<1e-8
