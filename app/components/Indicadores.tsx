type Ind = { codigo: string; indicador: string; valor: number; denominador: number | null; definicion: string };

export function Indicadores({ filas }: { filas: Ind[] }) {
  return (
    <div className="kpis">
      {filas.map((i) => (
        <div className="kpi" key={i.codigo}>
          <div className="d">{i.indicador}</div>
          <div className="v">
            {i.valor}
            {i.denominador !== null && <span className="d"> de {i.denominador}{i.denominador > 0 ? ` (${Math.round((i.valor / i.denominador) * 100)}%)` : ''}</span>}
          </div>
          <details><summary>Definición</summary>{i.definicion}</details>
        </div>
      ))}
    </div>
  );
}
