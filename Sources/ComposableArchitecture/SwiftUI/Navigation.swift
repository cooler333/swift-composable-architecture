import SwiftUI

public enum NavigationAction<Action> {
  case isActive(Action)
  case setNavigation(isActive: Bool)
}

extension NavigationAction: Equatable where Action: Equatable {}
extension NavigationAction: Hashable where Action: Hashable {}

extension Reducer {
  public func navigates<Route, LocalState, LocalAction, LocalEnvironment>(
    _ localReducer: Reducer<LocalState, LocalAction, LocalEnvironment>,
    tag: CasePath<Route, LocalState>,
    selection: WritableKeyPath<State, Route?>,
    action toNavigationAction: CasePath<Action, NavigationAction<LocalAction>>,
    environment toLocalEnvironment: @escaping (Environment) -> LocalEnvironment
  ) -> Self {
    let id = UUID()
    return Self { state, action, environment in
      let wasPresented = state[keyPath: selection].flatMap(tag.extract(from:)) != nil
      var effects: [Effect<Action, Never>] = []

      effects.append(
        localReducer
          ._pullback(
            state: OptionalPath(selection).appending(path: tag),
            action: toNavigationAction.appending(path: /NavigationAction.isActive),
            environment: toLocalEnvironment
          )
          .run(&state, action, environment)
          .cancellable(id: id)
      )

      effects.append(
        self
          .run(&state, action, environment)
      )

      if state[keyPath: selection].flatMap(tag.extract(from:)) != nil,
         case .some(.setNavigation(isActive: false)) = toNavigationAction.extract(from: action)
      {
        state[keyPath: selection] = nil
      }
      if wasPresented && state[keyPath: selection] == nil {
        effects.append(.cancel(id: id))
      }

      return .merge(effects)
    }
  }

  public func navigates<Route, LocalState, LocalAction, LocalEnvironment>(
    _ localReducer: Reducer<LocalState, LocalAction, LocalEnvironment>,
    tag: CasePath<Route, Void>,
    selection: WritableKeyPath<State, Route?>,
    state toLocalState: WritableKeyPath<State, LocalState>,
    action toNavigationAction: CasePath<Action, NavigationAction<LocalAction>>,
    environment toLocalEnvironment: @escaping (Environment) -> LocalEnvironment
  ) -> Self {
    let id = UUID()
    return Self { state, action, environment in
      let wasPresented = state[keyPath: selection].flatMap(tag.extract(from:)) != nil
      var effects: [Effect<Action, Never>] = []

      effects.append(
        localReducer
          .pullback(
            state: toLocalState,
            action: toNavigationAction.appending(path: /NavigationAction.isActive),
            environment: toLocalEnvironment
          )
          .run(&state, action, environment)
          .cancellable(id: id)
      )

      effects.append(
        self.run(&state, action, environment)
      )

      switch toNavigationAction.extract(from: action) {
      case .some(.setNavigation(isActive: true)):  // TODO: `where state[keyPath: selection] == nil:`?
        state[keyPath: selection] = nil

      case .some(.setNavigation(isActive: false))
            where state[keyPath: selection].flatMap(tag.extract(from:)) != nil:
        state[keyPath: selection] = nil

      default:
        break
      }
      if wasPresented && state[keyPath: selection] == nil {
        effects.append(.cancel(id: id))
      }

      return .merge(effects)
    }
  }

  public func navigates<LocalState, LocalAction, LocalEnvironment>(
    _ localReducer: Reducer<LocalState, LocalAction, LocalEnvironment>,
    state toLocalState: WritableKeyPath<State, LocalState?>,
    action toNavigationAction: CasePath<Action, NavigationAction<LocalAction>>,
    environment toLocalEnvironment: @escaping (Environment) -> LocalEnvironment
  ) -> Self {
    self.navigates(
      localReducer,
      tag: /.self,
      selection: toLocalState,
      action: toNavigationAction,
      environment: toLocalEnvironment
    )
  }
}

public struct NavigationLinkStore<Route, State, Action, Label, Destination>: View
where
  Label: View,
  Destination: View
{
  let destination: Destination
  let label: () -> Label
  let selection: Store<Bool, NavigationAction<Action>>

  public init<Content>(
    destination: @escaping (Store<State, Action>) -> Content,
    tag: CasePath<Route, State>,
    selection: Store<Route?, NavigationAction<Action>>,
    label: @escaping () -> Label
  ) where Destination == IfLetStore<State, Action, Content?> {
    self.destination = IfLetStore<State, Action, Content?>(
      selection.scope(
        state: { $0.flatMap(tag.extract(from:)) },
        action: NavigationAction.isActive
      ),
      then: destination
    )
    self.label = label
    self.selection = selection.scope(state: { $0.flatMap(tag.extract(from:)) != nil })
  }

  public init(
    destination: Destination,
    tag: CasePath<Route, Void>,
    selection: Store<Route?, NavigationAction<Action>>,
    label: @escaping () -> Label
  ) where State == Void {
    self.destination = destination
    self.label = label
    self.selection = selection.scope(state: { $0.flatMap(tag.extract(from:)) != nil })
  }

  public init<Content>(
    destination: @escaping (Store<State, Action>) -> Content,
    ifLet selection: Store<State?, NavigationAction<Action>>,
    label: @escaping () -> Label
  ) where Route == State, Destination == IfLetStore<State, Action, Content?> {
    self.init(
      destination: destination,
      tag: /.self,
      selection: selection,
      label: label
    )
  }

  public var body: some View {
    WithViewStore(self.selection) { viewStore in
      NavigationLink(
        destination: self.destination,
        isActive: viewStore
          .binding(send: NavigationAction.setNavigation(isActive:))
          .removeDuplicates(),
        label: self.label
      )
    }
  }
}

extension NavigationLinkStore where Label == Text {
  public init<Content>(
    titleKey: LocalizedStringKey,
    destination: @escaping (Store<State, Action>) -> Content,
    tag: CasePath<Route, State>,
    selection: Store<Route?, NavigationAction<Action>>
  ) where Destination == IfLetStore<State, Action, Content?> {
    self.init(
      destination: destination,
      tag: tag,
      selection: selection,
      label: { Text(titleKey) }
    )
  }

  public init<Content, S>(
    title: S,
    destination: @escaping (Store<State, Action>) -> Content,
    tag: CasePath<Route, State>,
    selection: Store<Route?, NavigationAction<Action>>
  ) where Destination == IfLetStore<State, Action, Content?>, S: StringProtocol {
    self.init(
      destination: destination,
      tag: tag,
      selection: selection,
      label: { Text(title) }
    )
  }

  public init(
    titleKey: LocalizedStringKey,
    destination: Destination,
    tag: CasePath<Route, Void>,
    selection: Store<Route?, NavigationAction<Action>>
  ) where State == Void {
    self.init(
      destination: destination,
      tag: tag,
      selection: selection,
      label: { Text(titleKey) }
    )
  }

  public init<S>(
    title: S,
    destination: Destination,
    tag: CasePath<Route, Void>,
    selection: Store<Route?, NavigationAction<Action>>
  ) where State == Void, S: StringProtocol {
    self.init(
      destination: destination,
      tag: tag,
      selection: selection,
      label: { Text(title) }
    )
  }

  public init<Content>(
    titleKey: LocalizedStringKey,
    destination: @escaping (Store<State, Action>) -> Content,
    ifLet selection: Store<State?, NavigationAction<Action>>
  ) where Route == State, Destination == IfLetStore<State, Action, Content?> {
    self.init(
      destination: destination,
      ifLet: selection,
      label: { Text(titleKey) }
    )
  }

  public init<Content, S>(
    title: S,
    destination: @escaping (Store<State, Action>) -> Content,
    ifLet selection: Store<State?, NavigationAction<Action>>
  ) where Route == State, Destination == IfLetStore<State, Action, Content?>, S: StringProtocol {
    self.init(
      destination: destination,
      ifLet: selection,
      label: { Text(title) }
    )
  }
}

extension Binding {
  func removeDuplicates() -> Binding where Value: Equatable {
    return .init(
      get: {
        self.wrappedValue
      },
      set: { newValue, transaction in
        guard newValue != self.wrappedValue else { return }
        if transaction.animation != nil {
          withTransaction(transaction) {
            self.wrappedValue = newValue
          }
        } else {
          self.wrappedValue = newValue
        }
      }
    )
  }
}