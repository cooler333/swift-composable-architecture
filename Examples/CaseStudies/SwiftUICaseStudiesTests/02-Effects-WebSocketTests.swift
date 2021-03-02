import Combine
import ComposableArchitecture
import XCTest

@testable import SwiftUICaseStudies

class WebSocketTests: XCTestCase {
  let scheduler = DispatchQueue.testScheduler

  func testWebSocketHappyPath() {
    let socketSubject = PassthroughSubject<WebSocketClient.Action, Never>()
    let receiveSubject = PassthroughSubject<WebSocketClient.Message, NSError>()

    let store = TestStore(
      initialState: .init(),
      reducer: webSocketReducer,
      environment: WebSocketEnvironment(
        mainQueue: self.scheduler.eraseToAnyScheduler(),
        webSocket: .mock(
          open: { _, _, _ in socketSubject.eraseToEffect() },
          receive: { _ in receiveSubject.eraseToEffect() },
          send: { _, _ in Effect(value: nil) },
          sendPing: { _ in .none }
        )
      )
    )

    // Connect to the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .connecting
    }

    socketSubject.send(.didOpenWithProtocol(nil))
    self.scheduler.advance()
    store.receive(.webSocket(.didOpenWithProtocol(nil))) {
      $0.connectivityState = .connected
    }

    // Send a message
    store.send(.messageToSendChanged("Hi")) {
      $0.messageToSend = "Hi"
    }
    store.send(.sendButtonTapped) {
      $0.messageToSend = ""
    }
    store.receive(.sendResponse(nil))

    // Receive a message
    receiveSubject.send(.string("Hi"))
    self.scheduler.advance()
    store.receive(.receivedSocketMessage(.success(.string("Hi")))) {
      $0.receivedMessages = ["Hi"]
    }

    // Disconnect from the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .disconnected
    }
  }

  func testWebSocketSendFailure() {
    let socketSubject = PassthroughSubject<WebSocketClient.Action, Never>()
    let receiveSubject = PassthroughSubject<WebSocketClient.Message, NSError>()

    let store = TestStore(
      initialState: .init(),
      reducer: webSocketReducer,
      environment: WebSocketEnvironment(
        mainQueue: self.scheduler.eraseToAnyScheduler(),
        webSocket: .mock(
          open: { _, _, _ in socketSubject.eraseToEffect() },
          receive: { _ in receiveSubject.eraseToEffect() },
          send: { _, _ in Effect(value: NSError(domain: "", code: 1)) },
          sendPing: { _ in .none }
        )
      )
    )

    // Connect to the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .connecting
    }

    socketSubject.send(.didOpenWithProtocol(nil))
    self.scheduler.advance()
    store.receive(.webSocket(.didOpenWithProtocol(nil))) {
      $0.connectivityState = .connected
    }

    // Send a message
    store.send(.messageToSendChanged("Hi")) {
      $0.messageToSend = "Hi"
    }
    store.send(.sendButtonTapped) {
      $0.messageToSend = ""
    }
    store.receive(.sendResponse(NSError(domain: "", code: 1))) {
      $0.alert = .init(title: .init("Could not send socket message. Try again."))
    }

    // Disconnect from the socket
    store.send(.connectButtonTapped) {
      $0.connectivityState = .disconnected
    }
  }

  func testWebSocketPings() {
    let socketSubject = PassthroughSubject<WebSocketClient.Action, Never>()
    let pingSubject = PassthroughSubject<NSError?, Never>()

    let store = TestStore(
      initialState: .init(),
      reducer: webSocketReducer,
      environment: WebSocketEnvironment(
        mainQueue: self.scheduler.eraseToAnyScheduler(),
        webSocket: .mock(
          open: { _, _, _ in socketSubject.eraseToEffect() },
          receive: { _ in .none },
          sendPing: { _ in pingSubject.eraseToEffect() }
        )
      )
    )

    store.send(.connectButtonTapped) {
      $0.connectivityState = .connecting
    }

    socketSubject.send(.didOpenWithProtocol(nil))
    self.scheduler.advance()
    store.receive(.webSocket(.didOpenWithProtocol(nil))) {
      $0.connectivityState = .connected
    }

    pingSubject.send(nil)
    self.scheduler.advance(by: .seconds(5))
    self.scheduler.advance(by: .seconds(5))
    store.receive(.pingResponse(nil))

    store.send(.connectButtonTapped) {
      $0.connectivityState = .disconnected
    }
  }

  func testWebSocketConnectError() {
    let socketSubject = PassthroughSubject<WebSocketClient.Action, Never>()

    let store = TestStore(
      initialState: .init(),
      reducer: webSocketReducer,
      environment: WebSocketEnvironment(
        mainQueue: self.scheduler.eraseToAnyScheduler(),
        webSocket: .mock(
          cancel: { _, _, _ in .fireAndForget { socketSubject.send(completion: .finished) } },
          open: { _, _, _ in socketSubject.eraseToEffect() },
          receive: { _ in .none },
          sendPing: { _ in .none }
        )
      )
    )

    store.send(.connectButtonTapped) {
      $0.connectivityState = .connecting
    }

    socketSubject.send(.didClose(code: .internalServerError, reason: nil))
    self.scheduler.advance()
    store.receive(.webSocket(.didClose(code: .internalServerError, reason: nil))) {
      $0.connectivityState = .disconnected
    }
  }
}

extension WebSocketClient {
  static func mock(
    cancel: @escaping (AnyHashable, URLSessionWebSocketTask.CloseCode, Data?) -> Effect<
      Never, Never
    > = { _, _, _ in fatalError() },
    open: @escaping (AnyHashable, URL, [String]) -> Effect<Action, Never> = { _, _, _ in
      fatalError()
    },
    receive: @escaping (AnyHashable) -> Effect<Message, NSError> = { _ in fatalError() },
    send: @escaping (AnyHashable, URLSessionWebSocketTask.Message) -> Effect<NSError?, Never> = {
      _, _ in fatalError()
    },
    sendPing: @escaping (AnyHashable) -> Effect<NSError?, Never> = { _in in fatalError() }
  ) -> Self {
    Self(
      cancel: cancel,
      open: open,
      receive: receive,
      send: send,
      sendPing: sendPing
    )
  }
}
