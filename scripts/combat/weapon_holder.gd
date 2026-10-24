class_name WeaponHolder
extends RefCounted
## Puts a holder on a humanoid's right hand so a weapon model (+Y = blade/shaft) points to the
## character's front, +Z up, in the rest pose. Used by the player and by guards.

const HAND_BONE := "hand.R"


## The holder node (child of a BoneAttachment3D on the hand), or null when the model has no hand bone.
static func add(model: Node3D) -> Node3D:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	var skel: Skeleton3D = skels[0]
	var bone := skel.find_bone(HAND_BONE)
	if bone < 0:
		return null
	var attach := BoneAttachment3D.new()
	attach.name = "RightHand"
	attach.bone_name = HAND_BONE
	skel.add_child(attach)
	var holder := Node3D.new()
	holder.name = "Weapon"
	attach.add_child(holder)
	var to_skel := skel.global_basis.orthonormalized().inverse()
	var fwd := (to_skel * model.global_basis.z).normalized()
	var up := (to_skel * Vector3.UP).normalized()
	holder.basis = skel.get_bone_global_rest(bone).basis.orthonormalized().inverse() * Basis(fwd.cross(up), fwd, up)
	return holder
