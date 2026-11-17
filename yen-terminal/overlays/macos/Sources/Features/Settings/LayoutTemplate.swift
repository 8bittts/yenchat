#if os(macOS)
import Foundation

// MARK: - Layout Templates

/// Pre-defined split layout presets applied via one click in Settings.
/// Each layout describes a tree of splits that replaces the focused surface's leaf node.
/// Case order defines the Settings UI grid order via `CaseIterable.allCases`.
enum LayoutTemplate: String, CaseIterable, Identifiable {
    case singlePane
    case threeColumns
    case rightStack
    case bottomStack
    case quad
    case eastward13
    case eastward21
    case eastward23
    case centerStage
    case threeColumnBottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singlePane: return "Single Pane"
        case .threeColumns: return "Three Columns"
        case .rightStack: return "Right Stack"
        case .bottomStack: return "Bottom Stack"
        case .quad: return "Quad"
        case .eastward13: return "Eastward 1-3"
        case .eastward21: return "Eastward 2-1"
        case .eastward23: return "Eastward 2-3"
        case .centerStage: return "Center Stage"
        case .threeColumnBottom: return "Three Column Bottom"
        }
    }

    /// Number of new surfaces to create (excludes the original focused surface).
    var newSurfaceCount: Int {
        nodeSpec?.newSurfaceCount ?? 0
    }

    /// Declarative layout tree used by buildTree and tests to keep mappings stable.
    indirect enum NodeSpec {
        case focused
        case new(Int)
        case split(direction: SplitTree<YEN.SurfaceView>.Direction, ratio: Double, left: NodeSpec, right: NodeSpec)

        var newSurfaceCount: Int {
            switch self {
            case .focused: return 0
            case .new(let index): return index + 1
            case .split(_, _, let left, let right):
                return max(left.newSurfaceCount, right.newSurfaceCount)
            }
        }
    }

    /// Structural layout description. This is the source of truth for both runtime tree
    /// generation and unit tests.
    var nodeSpec: NodeSpec? {
        switch self {
        case .singlePane:
            return nil

        case .threeColumns:
            // [focused | new0 | new1] — equal thirds (outer 1/3, inner 1/2)
            return .split(
                direction: .horizontal,
                ratio: 1.0 / 3.0,
                left: .focused,
                right: .split(direction: .horizontal, ratio: 0.5, left: .new(0), right: .new(1))
            )

        case .rightStack:
            // [focused | (new0 / new1)]
            return .split(
                direction: .horizontal,
                ratio: 0.5,
                left: .focused,
                right: .split(direction: .vertical, ratio: 0.5, left: .new(0), right: .new(1))
            )

        case .bottomStack:
            // [focused / (new0 | new1)]
            return .split(
                direction: .vertical,
                ratio: 0.5,
                left: .focused,
                right: .split(direction: .horizontal, ratio: 0.5, left: .new(0), right: .new(1))
            )

        case .quad:
            // 2x2 grid:
            // ┌──────────┬───────────┐
            // │ focused   │ newViews[0]│
            // ├──────────┼───────────┤
            // │ newViews[1]│ newViews[2]│
            // └──────────┴───────────┘
            return .split(
                direction: .horizontal,
                ratio: 0.5,
                left: .split(direction: .vertical, ratio: 0.5, left: .focused, right: .new(1)),
                right: .split(direction: .vertical, ratio: 0.5, left: .new(0), right: .new(2))
            )

        case .eastward13:
            // Left full height, right 3 equal rows:
            // ┌─────┬─────┐
            // │     │ new0│
            // │focus├─────┤
            // │     │ new1│
            // │     ├─────┤
            // │     │ new2│
            // └─────┴─────┘
            return .split(
                direction: .horizontal,
                ratio: 0.5,
                left: .focused,
                right: .split(
                    direction: .vertical,
                    ratio: 1.0 / 3.0,
                    left: .new(0),
                    right: .split(direction: .vertical, ratio: 0.5, left: .new(1), right: .new(2))
                )
            )

        case .eastward21:
            // Left 2 rows, right full height:
            // ┌─────┬─────┐
            // │focus│     │
            // ├─────┤new1 │
            // │new0 │     │
            // └─────┴─────┘
            return .split(
                direction: .horizontal,
                ratio: 0.5,
                left: .split(direction: .vertical, ratio: 0.5, left: .focused, right: .new(0)),
                right: .new(1)
            )

        case .eastward23:
            // Left 2 rows, right 3 equal rows:
            // ┌─────┬─────┐
            // │focus│ new1│
            // ├─────┼─────┤
            // │     │ new2│
            // │new0 ├─────┤
            // │     │ new3│
            // └─────┴─────┘
            return .split(
                direction: .horizontal,
                ratio: 0.5,
                left: .split(direction: .vertical, ratio: 0.5, left: .focused, right: .new(0)),
                right: .split(
                    direction: .vertical,
                    ratio: 1.0 / 3.0,
                    left: .new(1),
                    right: .split(direction: .vertical, ratio: 0.5, left: .new(2), right: .new(3))
                )
            )

        case .centerStage:
            // 3 columns, middle split into 2 rows:
            // ┌──────┬──────┬──────┐
            // │      │ new0 │      │
            // │focus ├──────┤ new2 │
            // │      │ new1 │      │
            // └──────┴──────┴──────┘
            return .split(
                direction: .horizontal,
                ratio: 1.0 / 3.0,
                left: .focused,
                right: .split(
                    direction: .horizontal,
                    ratio: 0.5,
                    left: .split(direction: .vertical, ratio: 0.5, left: .new(0), right: .new(1)),
                    right: .new(2)
                )
            )

        case .threeColumnBottom:
            // Top full width, bottom 3 equal columns:
            // ┌────────────────────┐
            // │      focused       │
            // ├──────┬──────┬──────┤
            // │ new0 │ new1 │ new2 │
            // └──────┴──────┴──────┘
            return .split(
                direction: .vertical,
                ratio: 0.5,
                left: .focused,
                right: .split(
                    direction: .horizontal,
                    ratio: 1.0 / 3.0,
                    left: .new(0),
                    right: .split(direction: .horizontal, ratio: 0.5, left: .new(1), right: .new(2))
                )
            )
        }
    }

    /// Stable string form for test assertions.
    var nodeSpecSignature: String? {
        guard let spec = nodeSpec else { return nil }
        return serialize(spec)
    }

    /// Build the layout subtree from the focused surface and newly created views.
    /// Returns nil for singlePane (handled as a special case in `applyLayout`).
    func buildTree(
        focused: YEN.SurfaceView,
        newViews: [YEN.SurfaceView]
    ) -> SplitTree<YEN.SurfaceView>.Node? {
        precondition(newViews.count == newSurfaceCount,
            "buildTree expects \(newSurfaceCount) views, got \(newViews.count)")

        guard let spec = nodeSpec else { return nil }
        return buildNode(from: spec, focused: focused, newViews: newViews)
    }

    private func serialize(_ spec: NodeSpec) -> String {
        switch spec {
        case .focused:
            return "F"
        case .new(let index):
            return "N\(index)"
        case .split(let direction, let ratio, let left, let right):
            let axis: String
            switch direction {
            case .horizontal: axis = "H"
            case .vertical: axis = "V"
            }
            return String(format: "%@%.4f(%@,%@)", axis, ratio, serialize(left), serialize(right))
        }
    }

    private func buildNode(
        from spec: NodeSpec,
        focused: YEN.SurfaceView,
        newViews: [YEN.SurfaceView]
    ) -> SplitTree<YEN.SurfaceView>.Node {
        switch spec {
        case .focused:
            return .leaf(view: focused)

        case .new(let index):
            precondition(index >= 0 && index < newViews.count,
                "layout spec references newViews[\(index)] but only \(newViews.count) are available")
            return .leaf(view: newViews[index])

        case .split(let direction, let ratio, let left, let right):
            return .split(.init(
                direction: direction,
                ratio: ratio,
                left: buildNode(from: left, focused: focused, newViews: newViews),
                right: buildNode(from: right, focused: focused, newViews: newViews)
            ))
        }
    }
}

#endif // os(macOS)
