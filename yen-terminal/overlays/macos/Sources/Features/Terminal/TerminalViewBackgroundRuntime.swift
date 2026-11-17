import AppKit
import SwiftUI
import YENKit

extension TerminalView {
    func syncWholeWindowBackgroundRuntime(sourceConfig: YEN.Config? = nil) {
        guard !viewModel.surfaceTree.isEmpty else {
            if wholeWindowBackgroundRuntimeActive {
                settingsController.removeWholeWindowBackgroundRuntimeConfigIfPresent()
                wholeWindowBackgroundRuntimeActive = false
            }
            return
        }

        let sourceConfig = sourceConfig ?? yen.config
        if shouldRenderWholeWindowBackgroundImage {
            applyWholeWindowBackgroundRuntime(sourceConfig: sourceConfig)
        } else if wholeWindowBackgroundRuntimeActive {
            restoreWholeWindowBackgroundRuntime(sourceConfig: sourceConfig)
        } else {
            settingsController.removeWholeWindowBackgroundRuntimeConfigIfPresent()
        }
    }

    private func applyWholeWindowBackgroundRuntime(sourceConfig: YEN.Config) {
        applySurfaceBackgroundRuntime(useWholeWindowOverride: true, sourceConfig: sourceConfig)
    }

    private func applySurfaceBackgroundRuntime(useWholeWindowOverride: Bool, sourceConfig: YEN.Config) {
        do {
            let runtimeConfigPath = settingsController.wholeWindowBackgroundRuntimeConfigPath
            let runtimeConfig = try TerminalBackgroundRuntimeConfigCache.shared.resolve(
                sourceConfig: sourceConfig, snapshot: settingsSnapshot, runtimePath: runtimeConfigPath,
                useWholeWindowOverride: useWholeWindowOverride
            ) {
                try settingsController.writeSurfaceBackgroundRuntimeConfig(
                    useWholeWindowOverride: useWholeWindowOverride
                )
                let runtimeConfig = YEN.Config(at: runtimeConfigPath)
                return runtimeConfig
            }
            guard runtimeConfig.loaded, let config = runtimeConfig.config else {
                YEN.logger.warning(
                    "whole-window background: runtime config failed to load path=\(runtimeConfigPath)"
                )
                if useWholeWindowOverride {
                    restoreWholeWindowBackgroundRuntime(sourceConfig: sourceConfig)
                } else {
                    reloadSurfaceConfigsFromCurrentAppConfig()
                    settingsController.removeWholeWindowBackgroundRuntimeConfigIfPresent()
                    wholeWindowBackgroundRuntimeActive = false
                }
                return
            }

            for surfaceView in viewModel.surfaceTree {
                guard let surface = surfaceView.surface else { continue }
                yen_surface_update_config(surface, config)
            }

            wholeWindowBackgroundRuntimeActive = useWholeWindowOverride
            if !useWholeWindowOverride {
                settingsController.removeWholeWindowBackgroundRuntimeConfigIfPresent()
            }
        } catch {
            YEN.logger.warning(
                "whole-window background: runtime config write failed error=\(error.localizedDescription)"
            )
            if useWholeWindowOverride {
                restoreWholeWindowBackgroundRuntime(sourceConfig: sourceConfig)
            } else {
                reloadSurfaceConfigsFromCurrentAppConfig()
                settingsController.removeWholeWindowBackgroundRuntimeConfigIfPresent()
                wholeWindowBackgroundRuntimeActive = false
            }
        }
    }

    private func restoreWholeWindowBackgroundRuntime(sourceConfig: YEN.Config) {
        if !settingsSnapshot.backgroundImagePath.isEmpty {
            applySurfaceBackgroundRuntime(useWholeWindowOverride: false, sourceConfig: sourceConfig)
            return
        }
        reloadSurfaceConfigsFromCurrentAppConfig()
        settingsController.removeWholeWindowBackgroundRuntimeConfigIfPresent()
        wholeWindowBackgroundRuntimeActive = false
    }

    private func reloadSurfaceConfigsFromCurrentAppConfig() {
        for surfaceView in viewModel.surfaceTree {
            guard let surface = surfaceView.surface else { continue }
            yen.reloadConfig(surface: surface, soft: true)
        }
    }
}
