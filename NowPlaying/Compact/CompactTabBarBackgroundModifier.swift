//
//  NowPlayingBar.swift
//  Music
//
//  Created by Rasmus Krämer on 07.09.23.
//

import SwiftUI
import AmpFinKit

internal extension NowPlaying {
    struct CompactTabBarBackgroundModifier: ViewModifier {
        @Environment(ViewModel.self) private var viewModel
        
        func body(content: Content) -> some View {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                // The system tab bar is Liquid Glass already.
                content
            } else {
                legacy(content)
            }
            #else
            legacy(content)
            #endif
        }
        
        private func legacy(_ content: Content) -> some View {
            content
                .safeAreaInset(edge: .bottom) {
                    // Tab bar background
                    if viewModel.nowPlaying != nil {
                        Rectangle()
                            .frame(height: 300)
                            .mask {
                                VStack(spacing: 0) {
                                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                                        .frame(height: 50)
                                    
                                    Rectangle()
                                        .frame(height: 250)
                                }
                            }
                            .foregroundStyle(.bar)
                            .padding(.bottom, -225)
                            .allowsHitTesting(false)
                            .toolbarBackground(.hidden, for: .tabBar)
                            .ignoresSafeArea(.keyboard)
                            .ignoresSafeArea(edges: .all)
                    }
                }
        }
    }
}
