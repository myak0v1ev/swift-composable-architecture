import ComposableArchitecture
import SwiftUI

private let readMe = """
  This screen demonstrates how to use NavigationStack with Composable Architecture applications.
  """

struct NavigationStackDemo: ReducerProtocol {
  @Dependency(\.navigationID.next) var nextID

  struct State: Equatable, NavigableState {
    var path = NavigationState<Route>()
    var total = 0
    var currentStack: [String] = []

    enum Route: Codable, Equatable, Hashable {
      case screenA(ScreenA.State)
      case screenB(ScreenB.State)
      case screenC(ScreenC.State)
    }
  }

  enum Action: Equatable, NavigableAction {
    case goBackToScreen(Int)
    case goToABCButtonTapped
    case navigation(NavigationAction<State.Route, Route>)
    case shuffleButtonTapped
    case cancelTimersButtonTapped

    enum Route: Equatable {
      case screenA(ScreenA.Action)
      case screenB(ScreenB.Action)
      case screenC(ScreenC.Action)
    }
  }

  var body: some ReducerProtocol<State, Action> {
    Reduce { state, action in
      switch action {
      case let .goBackToScreen(index):
        state.path = state.path.dropLast(state.path.count - index - 1)
        return .none

      case .goToABCButtonTapped:
        state.path.append(.init(id: self.nextID(), element: .screenA(.init())))
        state.path.append(.init(id: self.nextID(), element: .screenB(.init())))
        state.path.append(.init(id: self.nextID(), element: .screenC(.init())))
        return .none

      case .shuffleButtonTapped:
        state.path = NavigationState(path: .init(uniqueElements: state.path.shuffled()))
        return .none

      case .navigation(.element(id: _, .screenB(.screenAButtonTapped))):
        state.path.append(.init(id: self.nextID(), element: .screenA(.init())))
        return .none

      case .navigation:
        return .none

      case .cancelTimersButtonTapped:
        return .merge(state.path.compactMap { state in
          switch state.element {
          case .screenA, .screenB:
            return nil
            
          case .screenC:
            return .cancel(id: state.id)
          }
        })
      }
    }
    // TODO: figure out destinations builder
    .navigationDestination {
      // NB: Using explicit CasePath(...) due to Swift compiler bugs
      PullbackCase(state: CasePath(State.Route.screenA), action: CasePath(Action.Route.screenA)) {
        ScreenA()
      }
    }
    .navigationDestination {
      PullbackCase(state: CasePath(State.Route.screenB), action: CasePath(Action.Route.screenB)) {
        ScreenB()
      }
    }
    .navigationDestination {
      PullbackCase(state: CasePath(State.Route.screenC), action: CasePath(Action.Route.screenC)) {
        ScreenC()
      }
    }

    Reduce { state, action in
      state.total = 0
      state.currentStack = []
      for route in state.path {
        switch route.element {
        case let .screenA(screenAState):
          state.total += screenAState.count
          state.currentStack.append("Screen A")
        case .screenB:
          state.currentStack.append("Screen B")
        case let .screenC(screenBState):
          state.total += screenBState.count
          state.currentStack.append("Screen C")
        }
      }
      return .none
    }
  }
}

struct NavigationStackView: View {
  let store: StoreOf<NavigationStackDemo>

  var body: some View {
    ZStack(alignment: .bottom) {
      NavigationStackStore(store: self.store) {
        Form {
          Section { Text(readMe) }

          Section{
            NavigationLink(route: NavigationStackDemo.State.Route.screenA(.init())) {
              Text("Go to screen A")
            }
            NavigationLink(route: NavigationStackDemo.State.Route.screenB(.init())) {
              Text("Go to screen B")
            }
            NavigationLink(route: NavigationStackDemo.State.Route.screenC(.init())) {
              Text("Go to screen C")
            }
          }

          WithViewStore(self.store.stateless) { viewStore in
            Section {
              Button("Go to A → B → C") {
                viewStore.send(.goToABCButtonTapped)
              }
            }
          }
        }
        .navigationDestination(store: self.store) {
          DestinationStore(
            // NB: Using explicit CasePath(...) due to Swift compiler bugs
            state: CasePath(NavigationStackDemo.State.Route.screenA).extract(from:),
            action: NavigationStackDemo.Action.Route.screenA,
            content: ScreenAView.init(store:)
          )
          DestinationStore(
            state: CasePath(NavigationStackDemo.State.Route.screenB).extract(from:),
            action: NavigationStackDemo.Action.Route.screenB,
            content: ScreenBView.init(store:)
          )
          DestinationStore(
            state: CasePath(NavigationStackDemo.State.Route.screenC).extract(from:),
            action: NavigationStackDemo.Action.Route.screenC,
            content: ScreenCView.init(store:)
          )
        }
        .navigationTitle("Navigation Stack")
      }
      .zIndex(0)

      FloatingMenuView(store: self.store)
        .zIndex(1)
    }
  }
}

struct FloatingMenuView: View {
  let store: StoreOf<NavigationStackDemo>

  struct State: Equatable {
    let currentStack: [String]
    let total: Int
    init(state: NavigationStackDemo.State) {
      self.currentStack = state.currentStack
      self.total = state.total
    }
  }

  var body: some View {
    WithViewStore(self.store.scope(state: State.init)) { viewStore in
      if viewStore.currentStack.count > 0 {
        VStack(alignment: .leading) {
          Text("Total count: \(viewStore.total)")
          Button("Shuffle navigation stack") {
            viewStore.send(.shuffleButtonTapped)
          }
          Button("Pop to root") {
            // TODO: choose style
            viewStore.send(.popToRoot)
//            viewStore.send(.navigation(.setPath([])))
//            viewStore.send(.navigation(.removeAll))
          }
          Button("Cancel timers") {
            viewStore.send(.cancelTimersButtonTapped)
          }

          Menu {
            ForEach(Array(viewStore.currentStack.enumerated().reversed()), id: \.offset) { offset, screen in
              Button("\(offset + 1).) \(screen)") {
                viewStore.send(.goBackToScreen(offset))
              }
              .disabled(offset == viewStore.currentStack.count - 1)
            }
            Button("Root") { viewStore.send(.popToRoot) }
          } label: {
            Text("Current stack")
          }
        }
        .padding()
        .background(Color.white)
        .padding(.bottom, 1)
        .transition(.opacity.animation(.default))
      }
    }
  }
}

struct ScreenA: ReducerProtocol {
  @Dependency(\.factClient) var fact

  struct State: Codable, Equatable, Hashable {
    var count = 0
    var fact: String?
    var isLoading = false
  }
  enum Action: Equatable {
    case decrementButtonTapped
    case incrementButtonTapped
    case factButtonTapped
    case factResponse(TaskResult<String>)
  }

  func reduce(into state: inout State, action: Action) -> Effect<Action, Never> {
    switch action {
    case .decrementButtonTapped:
      state.count -= 1
      return .none

    case .incrementButtonTapped:
      state.count += 1
      return .none

    case .factButtonTapped:
      state.isLoading = true
      return .task { [count = state.count] in
        await .factResponse(.init { try await self.fact.fetch(count) })
      }

    case let .factResponse(.success(fact)):
      state.isLoading = false
      state.fact = fact
      return .none

    case .factResponse(.failure):
      state.isLoading = false
      state.fact = nil
      // TODO: error handling
      return .none
    }
  }
}

struct ScreenAView: View {
  let store: StoreOf<ScreenA>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      Form {
        Section {
          HStack {
            Text("\(viewStore.count)")
            Spacer()
            Button("-") { viewStore.send(.decrementButtonTapped) }
            Button("+") { viewStore.send(.incrementButtonTapped) }
          }
          .buttonStyle(.borderless)

          Button(action: { viewStore.send(.factButtonTapped) }) {
            HStack {
              Text("Get fact")
              Spacer()
              if viewStore.isLoading {
                ProgressView()
              }
            }
          }

          if let fact = viewStore.fact {
            Text(fact)
          }
        }

        Section {
          NavigationLink(route: NavigationStackDemo.State.Route.screenA(.init(count: viewStore.count))) {
            Text("Go to screen A")
          }
          NavigationLink(route: NavigationStackDemo.State.Route.screenB(.init())) {
            Text("Go to screen B")
          }
          NavigationLink(route: NavigationStackDemo.State.Route.screenC(.init())) {
            Text("Go to screen C")
          }
        }
      }
    }
    .navigationTitle("Screen A")
  }
}

struct ScreenB: ReducerProtocol {
  struct State: Codable, Equatable, Hashable {}
  enum Action: Equatable {
    case screenAButtonTapped
  }

  func reduce(into state: inout State, action: Action) -> Effect<Action, Never> {
    switch action {
    case .screenAButtonTapped:
      return .none
    }
  }
}
struct ScreenBView: View {
  let store: StoreOf<ScreenB>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      Form {
        Button("Decoupled navigation to screen A") {
          viewStore.send(.screenAButtonTapped)
        }
      }
      .navigationTitle("Screen B")
    }
  }
}

struct ScreenC: ReducerProtocol {
  enum TimerId {}
  @Dependency(\.mainQueue) var mainQueue

  struct State: Codable, Equatable, Hashable {
    var count = 0
    var isTimerRunning = false
  }
  enum Action: Equatable {
    case startButtonTapped
    case stopButtonTapped
    case timerTick
  }
  func reduce(into state: inout State, action: Action) -> Effect<Action, Never> {

    switch action {
    case .startButtonTapped:
      state.isTimerRunning = true
      return Effect.timer(id: TimerId.self, every: 1, on: self.mainQueue)
        .map { _ in .timerTick }

    case .stopButtonTapped:
      state.isTimerRunning = false
      return .cancel(id: TimerId.self)

    case .timerTick:
      state.count += 1
      return .none
    }
  }
}
struct ScreenCView: View {
  let store: StoreOf<ScreenC>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      Form {
        Section {
          Text("\(viewStore.count)")
          if viewStore.isTimerRunning {
            Button("Stop timer") { viewStore.send(.stopButtonTapped) }
          } else {
            Button("Start timer") { viewStore.send(.startButtonTapped) }
          }
        }

        Section {
          NavigationLink(route: NavigationStackDemo.State.Route.screenA(.init(count: viewStore.count))) {
            Text("Go to screen A")
          }
          NavigationLink(route: NavigationStackDemo.State.Route.screenB(.init())) {
            Text("Go to screen B")
          }
          NavigationLink(route: NavigationStackDemo.State.Route.screenC(.init())) {
            Text("Go to screen C")
          }
        }
      }
      .navigationTitle("Screen C")
    }
  }
}

struct NavigationStack_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStackView(
      store: .init(
        initialState: .init(),
        reducer: NavigationStackDemo()
      )
    )
  }
}
