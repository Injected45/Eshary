const errors: Record<string, string> = {
  forbidden: 'ليست لديك صلاحية لفتح هذه الشاشة',
};

/** Result of the last action, carried in the address (?ok= / ?err=). */
export function Flash({ ok, err }: { ok?: string; err?: string }) {
  const bad = err ? (errors[err] ?? err) : null;
  return (
    <>
      {ok ? <p className="flash ok">{ok}</p> : null}
      {bad ? <p className="flash bad">{bad}</p> : null}
    </>
  );
}
