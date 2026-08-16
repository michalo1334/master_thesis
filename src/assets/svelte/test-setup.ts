import "@testing-library/jest-dom/vitest";
import { afterEach, vi } from "vitest";

class ResizeObserverMock {
  static instances = new Set<ResizeObserverMock>();
  private targets = new Set<Element>();

  constructor(private readonly callback: ResizeObserverCallback) {
    ResizeObserverMock.instances.add(this);
  }

  observe(target: Element) {
    this.targets.add(target);
  }

  unobserve(target: Element) {
    this.targets.delete(target);
  }

  disconnect() {
    this.targets.clear();
    ResizeObserverMock.instances.delete(this);
  }

  static notify() {
    for (const observer of ResizeObserverMock.instances) {
      observer.callback(
        [...observer.targets].map(
          (target) =>
            ({
              target,
              contentRect: { height: target.clientHeight },
            }) as ResizeObserverEntry,
        ),
        observer as unknown as ResizeObserver,
      );
    }
  }
}

vi.stubGlobal("ResizeObserver", ResizeObserverMock);

// Bits UI defers body-scroll cleanup by 24ms after a dialog unmounts.
afterEach(() => new Promise((resolve) => setTimeout(resolve, 25)));
