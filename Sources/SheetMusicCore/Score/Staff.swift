import Foundation

/// A single staff inside a `Part`. Unifies what was previously split
/// across `StaffDeclaration` (rendering hints, defaultClef) and
/// `StaffContent` (measures). Lives nested under its owning `Part`,
/// so order in `Part.staves` defines display order and identity.
///
/// C++: combines `mu::engraving::Staff` and the per-staff measure
/// chain that hangs off `Score`. The mscx file format keeps these
/// physically separated (`<Part><Staff id="N">` declares; top-level
/// `<Staff id="N">` carries measures). They are paired by id in the
/// decoder; the model collapses the split.
public struct Staff: Sendable, Equatable {
    /// MuseScore `<StaffType><name>` (e.g. "stdNormal", "tab6StrCommon").
    public var staffType: String
    /// MuseScore `<StaffType group="…">` — "pitched", "percussion",
    /// or "tablature".
    public var group: String
    /// Typed `<StaffType>` children beyond name/group: line count,
    /// line distance, generated-element flags, and (for tablature
    /// staves) the tab presentation style.
    public var typeProperties: StaffTypeProperties
    /// Index within the owning part of the staff this one is linked
    /// to (MuseScore `<linkedTo>`, converted from the score-global
    /// staff id by the decoder). A standard+tab guitar pair links the
    /// tab staff to the standard staff. `nil` when unlinked. Both
    /// staves of a linked pair carry full measure content in the
    /// file, so rendering needs no link semantics — but playback
    /// should skip linked copies to avoid doubling every note.
    public var linkedToStaffOffset: Int?
    /// MuseScore `<defaultClef>` (e.g. "G", "F", "PERC"). Layout
    /// engines synthesize the opening clef from this when the first
    /// content measure lacks an explicit `<Clef>`.
    public var defaultClefType: String?
    /// MuseScore `<bracket>` children of `<Staff>`, in document order.
    /// Each item anchors one bracket / brace whose span extends
    /// downward from this staff. Empty by default; callers that need
    /// auto-derivation from instrument family must populate this list
    /// themselves before handing the `Score` to the layout engine.
    public var brackets: [BracketItem]
    public var measures: [Measure]

    public init(
        staffType: String = "stdNormal",
        group: String = "pitched",
        typeProperties: StaffTypeProperties = StaffTypeProperties(),
        linkedToStaffOffset: Int? = nil,
        defaultClefType: String? = nil,
        brackets: [BracketItem] = [],
        measures: [Measure] = [],
    ) {
        self.staffType = staffType
        self.group = group
        self.typeProperties = typeProperties
        self.linkedToStaffOffset = linkedToStaffOffset
        self.defaultClefType = defaultClefType
        self.brackets = brackets
        self.measures = measures
    }

    /// True when this staff's group is "tablature". Convenience for
    /// the layout/rendering layers' staff-kind dispatch.
    public var isTablature: Bool {
        group == "tablature"
    }
}
