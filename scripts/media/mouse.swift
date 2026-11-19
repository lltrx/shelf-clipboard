// Mouse clicks and drags at screen points (origin at the top left of the main screen, as windows.swift
// prints them). Needs Accessibility permission for the terminal running it.
//
//   mouse click X Y
//   mouse drag X1 Y1 X2 Y2      press, move in small steps, release (Grab Text from Screen, Markup)
import CoreGraphics
import Foundation

let a = Array(CommandLine.arguments.dropFirst())

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func number(_ i: Int) -> Double {
    guard i < a.count, let value = Double(a[i]) else {
        FileHandle.standardError.write("usage: mouse click X Y | mouse drag X1 Y1 X2 Y2\n".data(using: .utf8)!)
        exit(2)
    }
    return value
}

switch a.first {
case "click":
    let p = CGPoint(x: number(1), y: number(2))
    post(.mouseMoved, p)
    usleep(120_000)
    post(.leftMouseDown, p)
    usleep(60_000)
    post(.leftMouseUp, p)
case "drag":
    let start = CGPoint(x: number(1), y: number(2)), end = CGPoint(x: number(3), y: number(4))
    post(.mouseMoved, start)
    usleep(150_000)
    post(.leftMouseDown, start)
    usleep(200_000)
    let steps = 30
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        usleep(16_000)
    }
    usleep(200_000)
    post(.leftMouseUp, end)
default:
    FileHandle.standardError.write("usage: mouse click X Y | mouse drag X1 Y1 X2 Y2\n".data(using: .utf8)!)
    exit(2)
}
