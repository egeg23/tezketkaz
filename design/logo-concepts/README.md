# TezKetKaz — концепты логотипа

4 варианта в SVG (масштабируется без потери качества, легко конвертится в PNG любого размера через `rsvg-convert` или `inkscape`).

## Concept 1: Arrow T (оранжевый градиент)
Стилизованная буква T где горизонтальная перекладина — стрелка вправо. Минималистичный, читабельный в 44×44px (iPhone home screen). Цвета: тёплый оранжевый → красный градиент. Ассоциация: скорость + направление.

## Concept 2: Courier Bag (бирюзовый)
Курьерская сумка с motion lines (волнами скорости) сзади. На сумке мини-логотип T. Цвета: teal/бирюзовый — азиатская палитра, отличается от Wolt (синий) и Glovo (жёлтый). Ассоциация: курьер + доставка.

## Concept 3: Pin + Lightning (тёмно-синий + жёлтый)
Map pin с молнией внутри. Цвета: deep navy + golden yellow. Ассоциация: место + скорость. Похож на Foodpanda стилистически, но более премиальный.

## Concept 4: Monogram TK (красный → оранжевый градиент)
Геометрическая монограмма TK с динамической K-стрелкой. Цвета: огненный градиент. Ассоциация: бренд-инициалы + динамика. Самый "корпоративный" вариант.

## Конверсия в PNG (когда выберешь)

```bash
# Установить rsvg-convert (один раз)
apt install librsvg2-bin

# Сгенерировать все размеры из выбранного SVG
for size in 1024 512 256 192 144 96 72 48; do
  rsvg-convert -w $size -h $size concept-X.svg > icon-${size}.png
done
```

Или через `flutter_launcher_icons` — указать путь к `1024×1024.png` и пакет сам сгенерирует все размеры под iOS + Android.

## Промпты для AI-генератора (если хочешь альтернативу через DALL-E/Midjourney)

- "Minimalist app icon for delivery service named TezKetKaz, stylized letter T with arrow, warm orange and red gradient, rounded square 1024x1024, flat vector style, no text, centered"
- "Mobile app icon, courier bag with motion lines, teal and white, flat design, geometric, 1024x1024, no text"
- "App icon, map pin with lightning bolt inside, navy blue background with golden yellow bolt, premium look, 1024x1024, flat vector"
