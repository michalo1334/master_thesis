import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import OptionPickerDialog from "./OptionPickerDialog.svelte";

interface Option {
  id: string;
  title: string;
  description?: string;
  disabled?: boolean;
}

const OptionPicker = OptionPickerDialog as typeof OptionPickerDialog<Option>;

const options: Option[] = [
  { id: "alpha", title: "Alpha", description: "First option" },
  { id: "beta", title: "Beta", description: "Second option" },
  { id: "gamma", title: "Gamma", disabled: true },
];

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

function renderDialog(overrides: Partial<Record<string, unknown>> = {}) {
  const onOpenChange = vi.fn();
  const defaultOnConfirm = vi.fn().mockResolvedValue(true);
  const onConfirm =
    (overrides.onConfirm as typeof defaultOnConfirm | undefined) ??
    defaultOnConfirm;

  render(OptionPicker, {
    props: {
      open: true,
      onOpenChange,
      items: options,
      title: "Choose options",
      description: "Choose one or more options.",
      getKey: (option: Option) => option.id,
      columns: [
        {
          key: "title",
          header: "Name",
          getValue: (option: Option) => option.title,
          filterable: true,
        },
        {
          key: "description",
          header: "Description",
          getValue: (option: Option) => option.description ?? "",
          filterable: true,
        },
      ],
      searchPlaceholder: "Search options…",
      emptyMessage: "No options.",
      noMatchMessage: "No options match.",
      isDisabled: (option: Option) => option.disabled ?? false,
      onConfirm,
      ...overrides,
    },
  });

  return { onOpenChange, onConfirm };
}

afterEach(cleanup);

describe("OptionPickerDialog", () => {
  it("uses radios for single selection and confirms the selected item", async () => {
    const { onConfirm, onOpenChange } = renderDialog();

    const alpha = screen.getByRole("radio", { name: "Select alpha" });
    const beta = screen.getByRole("radio", { name: "Select beta" });
    expect(screen.getByText("First option")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Select" })).toBeDisabled();

    await fireEvent.click(beta);

    expect(beta).toBeChecked();
    expect(alpha).not.toBeChecked();
    await fireEvent.click(screen.getByRole("button", { name: "Select" }));

    await waitFor(() => expect(onConfirm).toHaveBeenCalledWith([options[1]]));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it("uses checkboxes and returns multi-selection in source order", async () => {
    const { onConfirm } = renderDialog({ mode: "multiple" });

    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select beta" }),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select alpha" }),
    );
    await fireEvent.click(screen.getByRole("button", { name: "Select (2)" }));

    await waitFor(() =>
      expect(onConfirm).toHaveBeenCalledWith([options[0], options[1]]),
    );
  });

  it("does not permit disabled options to be selected", async () => {
    renderDialog({ mode: "multiple" });

    const gamma = screen.getByRole("checkbox", { name: "Select gamma" });
    expect(gamma).toBeDisabled();

    await fireEvent.click(gamma);

    expect(gamma).not.toBeChecked();
  });

  it("discards a draft selection when cancelled", async () => {
    const { onConfirm, onOpenChange } = renderDialog();

    await fireEvent.click(screen.getByRole("radio", { name: "Select alpha" }));
    await fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(onConfirm).not.toHaveBeenCalled();
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it("requires the configured minimum selection count", async () => {
    renderDialog({ mode: "multiple", minSelections: 2 });

    const select = screen.getByRole("button", { name: "Select (0)" });
    expect(select).toBeDisabled();

    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select alpha" }),
    );
    expect(screen.getByRole("button", { name: "Select (1)" })).toBeDisabled();

    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select beta" }),
    );
    expect(screen.getByRole("button", { name: "Select (2)" })).toBeEnabled();
  });

  it("ignores stale and disabled initial selections", () => {
    renderDialog({
      mode: "multiple",
      initialSelection: ["alpha", "gamma", "missing"],
    });

    expect(
      screen.getByRole("checkbox", { name: "Select alpha" }),
    ).toBeChecked();
    expect(
      screen.getByRole("checkbox", { name: "Select gamma" }),
    ).not.toBeChecked();
  });

  it("remains open when confirmation reports an expected failure", async () => {
    const { onConfirm, onOpenChange } = renderDialog({
      status: "Selection failed.",
      onConfirm: vi.fn().mockResolvedValue(false),
    });

    await fireEvent.click(screen.getByRole("radio", { name: "Select alpha" }));
    await fireEvent.click(screen.getByRole("button", { name: "Select" }));

    await waitFor(() => expect(onConfirm).toHaveBeenCalled());
    expect(onOpenChange).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toHaveTextContent("Selection failed.");
  });

  it("disables options and footer actions while confirmation is pending", async () => {
    const confirmation = deferred<boolean>();
    const onConfirm = vi.fn().mockReturnValue(confirmation.promise);
    renderDialog({ onConfirm });

    await fireEvent.click(screen.getByRole("radio", { name: "Select alpha" }));
    await fireEvent.click(screen.getByRole("button", { name: "Select" }));

    await waitFor(() => expect(onConfirm).toHaveBeenCalled());
    expect(screen.getByRole("radio", { name: "Select alpha" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Cancel" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Select" })).toBeDisabled();

    confirmation.resolve(false);
    await waitFor(() =>
      expect(screen.getByRole("radio", { name: "Select alpha" })).toBeEnabled(),
    );
  });

  it("shows a fallback error after rejected confirmation", async () => {
    renderDialog({
      onConfirm: vi.fn().mockRejectedValue(new Error("offline")),
    });

    await fireEvent.click(screen.getByRole("radio", { name: "Select alpha" }));
    await fireEvent.click(screen.getByRole("button", { name: "Select" }));

    expect(
      await screen.findByText(
        "Unable to complete the selection. Please try again.",
      ),
    ).toBeInTheDocument();
  });

  it("shows an empty message and disables confirmation without options", () => {
    renderDialog({ items: [] });

    expect(screen.getByText("No options.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Select" })).toBeDisabled();
  });

  it("filters the table by the search input", async () => {
    renderDialog();

    const search = screen.getByRole("searchbox");
    await fireEvent.input(search, { target: { value: "second" } });

    expect(
      screen.getByRole("radio", { name: "Select beta" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("radio", { name: "Select alpha" }),
    ).not.toBeInTheDocument();
  });
});
