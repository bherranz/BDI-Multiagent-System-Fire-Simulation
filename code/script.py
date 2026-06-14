import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd

# 1. Tu DataFrame con los datos reales
data = {
    'Escenario': ['01 - Base', '01 - Base', '02 - Viento Fuerte', '02 - Viento Fuerte', '03 - Flota Reducida', '03 - Flota Reducida'],
    'Modelo': ['Centralizado (CEN)', 'Descentralizado (DES)', 'Centralizado (CEN)', 'Descentralizado (DES)', 'Centralizado (CEN)', 'Descentralizado (DES)'],
    'Ciclos': [453, 732, 745, 532, 1133, 1630],
    'Ciclos_SD': [158, 608, 507, 558, 612, 1205],
    'Celdas': [2050, 5363, 8392, 3410, 6957, 14531],
    'Celdas_SD': [665, 6701, 9045, 4655, 5349, 16098],
    'Agua': [9206, 23247, 50403, 24593, 23749, 47972],
    'Agua_SD': [2023, 26640, 43159, 33333, 12155, 42219]
}

df = pd.DataFrame(data)

# Configuración estética global
sns.set_theme(style='whitegrid')
colors = ['#1f77b4', '#aec7e8']

metrics = [
    {'field': 'Ciclos', 'sd': 'Ciclos_SD', 'title': 'Tiempo de Extinción de la Simulación', 'ylabel': 'Ciclos promedio', 'filename': 'grafico_ciclos.png'},
    {'field': 'Celdas', 'sd': 'Celdas_SD', 'title': 'Superficie Total Quemada', 'ylabel': 'Celdas promedio', 'filename': 'grafico_celdas.png'},
    {'field': 'Agua', 'sd': 'Agua_SD', 'title': 'Consumo Total de Recursos Hídricos', 'ylabel': 'Litros promedio', 'filename': 'grafico_agua.png'}
]

# 2. Bucle para generar y guardar cada gráfico por separado
for m in metrics:
    # Creamos una figura independiente para cada métrica con un tamaño perfecto para el ancho de página
    fig, ax = plt.subplots(figsize=(8, 4.5))
    
    # Dibujar las barras
    sns.barplot(
        x='Escenario', 
        y=m['field'], 
        hue='Modelo', 
        data=df, 
        palette=colors,
        edgecolor='black',
        linewidth=1,
        ax=ax
    )
    
    # Añadir las barras de error (desviación típica)
    for i, bar in enumerate(ax.patches):
        df_idx = i if i < len(df) else i - len(df)
        x = bar.get_x() + bar.get_width() / 2
        y = bar.get_height()
        error = df.iloc[df_idx][m['sd']]
        ax.errorbar(x, y, yerr=error, fmt='none', c='black', capsize=5, elinewidth=1.2)
    
    # Pulir textos y etiquetas (ahora se verán grandes y legibles)
    ax.set_title(m['title'], fontsize=12, pad=10, fontweight='bold')
    ax.set_xlabel('Escenarios Experimentales', fontsize=10, labelpad=8)
    ax.set_ylabel(m['ylabel'], fontsize=10)
    ax.set_xticklabels(['01 - Escenario Base', '02 - Viento Fuerte', '03 - Flota Reducida'], fontsize=10)
    ax.legend(title='Arquitectura', loc='upper left', fontsize=9, title_fontsize=9)
    
    # Guardar cada gráfico con su nombre correspondiente
    plt.tight_layout()
    plt.savefig(m['filename'], dpi=300, bbox_inches='tight')
    plt.close() # Cierra la figura para liberar memoria

print("¡Gráficos generados correctamente: grafico_ciclos.png, grafico_celdas.png y grafico_agua.png!")