<svelte:options css="injected" />

<script lang="ts">
  import {
    draftOf,
    readDraft,
    type Compression,
    type DraftErrors,
    type SavedWebhook,
    type WebhookDraft,
  } from "../core/index.ts";
  import { postId } from "../dom/webhook.ts";
  import Sheet from "./Sheet.svelte";

  let {
    webhook,
    taken,
    onsubmit,
    ondelete,
    onclose,
  }: {
    /** The webhook to edit, or none for a new one. */
    webhook?: SavedWebhook;
    /** The names of the Share menu's other entries. */
    taken: string[];
    /** Saves a new webhook, or saves an edited one and sends the feedback to it. Returns why it could not save. */
    onsubmit: (webhook: SavedWebhook) => string | undefined;
    ondelete: () => string | undefined;
    onclose: () => void;
  } = $props();

  // The editor makes a new dialog each time it opens one, so the first value is the only one.
  // svelte-ignore state_referenced_locally
  let draft = $state<WebhookDraft>(draftOf(webhook));
  let errors = $state<DraftErrors>({});
  let failure = $state<string>();
  // svelte-ignore state_referenced_locally
  const id = webhook?.id ?? postId();
  const compressions: Compression[] = ["low", "medium", "high"];
  const list = new Intl.ListFormat("en", { type: "conjunction" });

  function submit() {
    const read = readDraft(draft, { id, taken });
    errors = "errors" in read ? read.errors : {};
    if ("webhook" in read) failure = onsubmit(read.webhook);
  }
</script>

{#snippet field(key: keyof DraftErrors, caption: string, placeholder: string, type?: "url")}
  <label>
    <span class="caption">{caption}</span>
    <input
      bind:value={draft[key]}
      {type}
      {placeholder}
      autocapitalize={key === "name" ? undefined : "off"}
      autocomplete="off"
      spellcheck={key === "name"}
      aria-invalid={!!errors[key]}
      aria-describedby={errors[key] ? `webhook-${key}-error` : undefined}
    />
    {#if errors[key]}<span class="error" id="webhook-{key}-error">{errors[key]}</span>{/if}
  </label>
{/snippet}

{#snippet segments(
  name: string,
  options: [string, string][],
  value: string,
  pick: (value: string) => void,
)}
  <div class="choice" role="radiogroup" aria-label={name}>
    <span>{name}</span>
    <div class="segments">
      {#each options as [option, label] (option)}
        <label class:picked={value === option}>
          <input
            type="radio"
            {name}
            value={option}
            checked={value === option}
            onchange={() => pick(option)}
          />{label}
        </label>
      {/each}
    </div>
  </div>
{/snippet}

<Sheet label={webhook ? "Edit Webhook" : "New Webhook"} onsubmit={submit}>
  {#snippet header()}
    {#if webhook}
      <button
        type="button"
        class="icon danger"
        aria-label="Delete Webhook"
        onclick={() => (failure = ondelete())}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"
          ><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3" /></svg
        >
      </button>
    {:else}
      <span class="icon"></span>
    {/if}
    <h2>{webhook ? webhook.name : "New Webhook"}</h2>
    <button type="button" class="icon" aria-label="Close" onclick={onclose}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
    </button>
  {/snippet}

  {#if failure}<p class="error" role="alert">{failure}</p>{/if}
  {@render field("name", "Name", "Agent")}
  {@render field("url", "URL", "https://hooks.example.com/feedback", "url")}
  {@render field("header", "Header (optional)", "Authorization: Bearer key")}

  <div class="list">
    <label class="toggle">
      <span>Attach JSON</span>
      <input type="checkbox" bind:checked={draft.feedback} />
    </label>
    <label class="toggle">
      <span>Attach image</span>
      <input type="checkbox" bind:checked={draft.image} />
    </label>
    {#if draft.image}
      {@render segments(
        "Image format",
        [
          ["png", "PNG"],
          ["jpeg", "JPEG"],
        ],
        draft.format,
        (value) => (draft.format = value as WebhookDraft["format"]),
      )}
      {#if draft.format === "jpeg"}
        {@render segments(
          "Compression",
          compressions.map((level) => [level, level[0]!.toUpperCase() + level.slice(1)]),
          draft.compression,
          (value) => (draft.compression = value as Compression),
        )}
      {/if}
    {/if}
  </div>
  <p class="note">
    Each post sends {list.format(
      [
        "the title",
        draft.feedback && "the feedback JSON",
        draft.image && "the image",
        "the device JSON",
      ].filter((part) => typeof part === "string"),
    )}. This browser keeps the webhook, header included, for this site.
  </p>
  <div class="actions">
    <button type="submit" class="primary">{webhook ? "Send" : "Save"}</button>
  </div>
</Sheet>

<style>
  .icon {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
  }

  .icon svg {
    width: 20px;
    height: 20px;
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  .danger {
    color: #ff453a;
  }

  input[aria-invalid="true"] {
    outline: 1px solid #ff453a;
  }

  .error {
    margin: 0;
    color: #ff6961;
    font-size: 13px;
  }

  .list {
    display: grid;
    border-radius: 10px;
    background: #2c2c2e;
    overflow: hidden;
  }

  .toggle,
  .choice {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    border-bottom: 1px solid rgb(255 255 255 / 0.08);
    padding: 11px 12px;
  }

  .list > :last-child {
    border-bottom: 0;
  }

  .toggle input {
    width: 20px;
    height: 20px;
    margin: 0;
    accent-color: #0a84ff;
  }

  .segments {
    display: flex;
    border-radius: 8px;
    padding: 2px;
    background: #1c1c1e;
  }

  .segments label {
    border-radius: 6px;
    padding: 4px 10px;
    font-size: 14px;
    cursor: pointer;
  }

  .segments label.picked {
    background: #636366;
  }

  .segments label:has(:focus-visible) {
    outline: 2px solid #0a84ff;
  }

  .segments input {
    position: absolute;
    opacity: 0;
    pointer-events: none;
  }

  .note {
    margin: 0;
    color: #aeaeb2;
    font-size: 13px;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
  }

  .primary {
    min-width: 96px;
    border-radius: 12px;
    padding: 10px 20px;
    background: #0a84ff;
    font-weight: 600;
  }
</style>
