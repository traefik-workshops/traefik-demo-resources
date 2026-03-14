interface Props {
  cols: number
  rows?: number
}

export default function SkeletonRow({ cols, rows = 5 }: Props) {
  return (
    <>
      {Array.from({ length: rows }).map((_, i) => (
        <tr key={i}>
          {Array.from({ length: cols }).map((_, j) => (
            <td key={j} className="px-4 py-3">
              <div
                className="h-3 rounded animate-pulse"
                style={{
                  background: 'var(--color-bg-tertiary)',
                  width: `${60 + Math.random() * 30}%`,
                }}
              />
            </td>
          ))}
        </tr>
      ))}
    </>
  )
}
