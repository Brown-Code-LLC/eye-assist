//
//  ContentView.swift
//  eye-assist
//
//  AudioVision root router: Onboarding on first launch, then Live.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Group {
            #if DEBUG
            // UI-testing hook: `-screen settings|history|onboarding` jumps straight there.
            if let forced = Self.forcedScreen {
                switch forced {
                case "settings": SettingsView()
                case "history": HistoryView()
                case "onboarding": OnboardingView()
                case "navigate": NavigateView()
                default: LiveView()
                }
            } else {
                routedRoot
            }
            #else
            routedRoot
            #endif
        }
        .environmentObject(model)
        .preferredColorScheme(.dark)
    }

    #if DEBUG
    private static let forcedScreen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }()
    #endif

    @ViewBuilder
    private var routedRoot: some View {
        if settings.onboardingComplete {
            LiveView()
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
}
