"use client";

import { useEffect, useRef, useState } from "react";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";

interface Props {
  value: Record<string, unknown> | null | undefined;
  onChange: (v: Record<string, unknown> | null) => void;
  disabled?: boolean;
  id?: string;
}

const HINT = `Examples:
  {"role": "BUYER"}
  {"country": "UZ", "lastOrderAfter": "2025-01-01"}
  {"shopId": "..."}`;

function safeStringify(v: Record<string, unknown> | null | undefined): string {
  if (!v) return "";
  try {
    return JSON.stringify(v, null, 2);
  } catch {
    return "";
  }
}

export function AudienceQueryEditor({ value, onChange, disabled, id }: Props) {
  const [text, setText] = useState<string>(safeStringify(value));
  const [error, setError] = useState<string | null>(null);
  // Track the last value we emitted so external resets reformat the textarea
  // but our own onChange-driven updates don't clobber the user's typing.
  const lastEmittedRef = useRef<Record<string, unknown> | null | undefined>(value);

  useEffect(() => {
    if (value !== lastEmittedRef.current) {
      setText(safeStringify(value));
      lastEmittedRef.current = value;
    }
  }, [value]);

  function onTextChange(next: string) {
    setText(next);
    if (next.trim() === "") {
      setError(null);
      lastEmittedRef.current = null;
      onChange(null);
      return;
    }
    try {
      const parsed = JSON.parse(next);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        setError(null);
        const obj = parsed as Record<string, unknown>;
        lastEmittedRef.current = obj;
        onChange(obj);
      } else {
        setError("Must be a JSON object");
      }
    } catch (e) {
      setError((e as Error).message);
    }
  }

  return (
    <div className="grid gap-2">
      <Label htmlFor={id ?? "audienceQuery"}>Audience query (JSON)</Label>
      <Textarea
        id={id ?? "audienceQuery"}
        value={text}
        disabled={disabled}
        onChange={(e) => onTextChange(e.target.value)}
        rows={8}
        className="font-mono text-xs"
        placeholder='{"role": "BUYER"}'
      />
      <div className="flex items-start justify-between gap-2 text-xs">
        <pre className="whitespace-pre-wrap text-muted-foreground">{HINT}</pre>
        {error && <span className="text-destructive">{error}</span>}
      </div>
    </div>
  );
}
