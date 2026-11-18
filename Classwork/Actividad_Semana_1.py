from pathlib import Path

import pandas as pd


CARPETA = Path(__file__).resolve().parent
ARCHIVO_ENTRADA = CARPETA / "Catalogo_Colaboradores.xlsx"
ARCHIVO_SALIDA = CARPETA / "archivo_actualizado.xlsx"
COLUMNAS_REQUERIDAS = (
    "Nombre Completo",
    "Sueldo Neto IMSS",
    "Sueldo Complementos",
    "Sueldo Neto Total",
)


def cargar_datos():
    return pd.read_excel(ARCHIVO_ENTRADA)


def limpieza_datos(df):
    faltantes = [columna for columna in COLUMNAS_REQUERIDAS if columna not in df.columns]
    if faltantes:
        raise ValueError(f"Faltan columnas requeridas en el Excel: {faltantes}")

    df = df.drop_duplicates().dropna(subset=COLUMNAS_REQUERIDAS).copy()
    df["Nombre Completo"] = df["Nombre Completo"].astype("string").str.strip().str.upper()
    df = df[df["Nombre Completo"].ne("")]
    return df


def crear_columnas(df):
    df = df.copy()
    df["SalarioDiario"] = df["Sueldo Neto Total"] / 192
    df["CostoInterno"] = df["Sueldo Neto IMSS"] + df["Sueldo Complementos"]
    return df


def estadisticasreferencia(df):
    return (
        df["SalarioDiario"].mean(),
        df["Sueldo Neto IMSS"].mean(),
        df["Sueldo Complementos"].mean(),
        df["CostoInterno"].mean(),
    )


def actualiza(df):
    df.to_excel(ARCHIVO_SALIDA, index=False)


def main():
    df = crear_columnas(limpieza_datos(cargar_datos()))
    salario_promedio, sueldo_imss_promedio, complementos_promedio, costo_interno_promedio = (
        estadisticasreferencia(df)
    )
    actualiza(df)

    print(f"Archivo actualizado: {ARCHIVO_SALIDA}")
    print(f"Registros procesados: {len(df)}")
    print(f"Salario diario promedio: {salario_promedio:.2f}")
    print(f"Sueldo IMSS promedio: {sueldo_imss_promedio:.2f}")
    print(f"Complementos promedio: {complementos_promedio:.2f}")
    print(f"Costo interno promedio: {costo_interno_promedio:.2f}")


if __name__ == "__main__":
    main()
