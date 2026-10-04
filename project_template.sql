/* Анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Доронин Олег
 * Дата:
*/



-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Продолжите запрос здесь
-- Используйте id объявлений (СТЕ filtered_id), которые не содержат выбросы при анализе данных
category_flats AS (
	SELECT
		CASE 
			WHEN re_city.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
			ELSE 'Ленинградская обл.'
		END AS category_city,
		CASE 
			WHEN days_exposition BETWEEN 1 AND 30 THEN '1-30 days'
			WHEN days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
			WHEN days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
			-- Исправление условия на >= 181
			WHEN days_exposition >= 181 THEN '181+ days'
			ELSE 'non category'
		END AS category_fl,
		count(re_adv.id) AS count_flats,
		-- Исправление. Добавление средней общей площади
		round(avg(re_flats.total_area)::numeric, 2) AS total_area,
		round(avg(re_adv.last_price / re_flats.total_area)::numeric, 2) AS square_metr,
		round(avg(re_flats.rooms)::NUMERIC, 2) AS avg_rooms,
		round(avg(re_flats.balcony)::NUMERIC, 2) AS avg_balcony,
		round(avg(re_flats.ceiling_height)::NUMERIC, 2) AS avg_ceiling_height,
		round(avg(re_flats.floor)::NUMERIC, 2) AS avg_floor
	FROM real_estate.advertisement AS re_adv
		INNER JOIN real_estate.flats AS re_flats
			ON re_adv.id = re_flats.id
		INNER JOIN real_estate.city AS re_city
			ON re_flats.city_id = re_city.city_id
		INNER JOIN real_estate.type AS re_type
			ON re_flats.type_id = re_type.type_id
	WHERE 
		re_adv.id IN (SELECT * FROM filtered_id)
		AND extract(YEAR FROM first_day_exposition) IN (2015, 2016, 2017, 2018)
		-- Исправление. Добавление условия 'город'
		AND re_type.type = 'город'
	GROUP BY 
		category_city,
		category_fl
),
sorted_category_flats AS (
	SELECT
		coalesce(category_city, 'All category_city') AS citees,
		coalesce(category_fl, 'All category_days') AS days,
		round(sum(count_flats)::numeric, 2) AS count_flats,
		-- Исправление. Добавление средней общей площади
		round(avg(total_area)::numeric, 2) AS total_area,
		round(avg(square_metr)::NUMERIC, 2) AS square_metr,
		round(avg(avg_rooms)::NUMERIC, 2) AS avg_rooms,
		round(avg(avg_balcony)::NUMERIC, 2) AS avg_balcony,
		round(avg(avg_ceiling_height)::NUMERIC, 2) AS avg_ceiling_height,
		round(avg(avg_floor)::NUMERIC, 2) AS avg_floor
	FROM category_flats
	GROUP BY rollup(category_city, category_fl)
	ORDER BY
		CASE 
			WHEN category_city = 'Санкт-Петербург' THEN 0
			ELSE 1
		END,
		category_city,
		CASE
			WHEN category_fl = '1-30 days' THEN 0
			WHEN category_fl = '31-90 days' THEN 1
			WHEN category_fl = '91-180 days' THEN 2
			WHEN category_fl = '181+ days' THEN 3
			ELSE 4
		END,
		category_fl
)
SELECT
	*
FROM sorted_category_flats
-- 1. Какие категории объявлений являются самыми распространёнными в Санкт-Петербурге и городах Ленинградской области?

-- Объявления за 2015–2018 гг.
-- Всего после удаления выбросов осталось 14 045 объявлений (СПб — 11 217, Лен. область — 2 828).
-- Из них 6,05% (851 шт.) не попали ни в одну категорию — это активные объявления или записи без даты.


-- Санкт-Петербург (без non category — 10 564):

-- 1–30 дней: 17,0% (1 794) — быстрые продажи
-- 31–90 дней: 28,6% (3 020)
-- 91–180 дней: 21,3% (2 244)
-- 181+ дней: 33,2% (3 506) — самый большой сегмент; каждая третья квартира продаётся дольше полугода


-- Ленинградская область (без non category — 2 630):

-- 1–30 дней: 12,9% (340)
-- 31–90 дней: 32,85% (864)
-- 91–180 дней: 21,02% (553)
-- 181+ дней: 33,19% (873) — самый большой сегмент; каждая третья квартира продаётся дольше полугода

	
	
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, 
-- среднюю стоимость квадратного метра, количество комнат и балконов 
-- и другие параметры, влияют на время активности объявлений? Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?
  

-- Площадь квартиры
-- СПб: 54,7 м² (быстрые) → 65,8 м² (долгие), рост на 20%
-- Лен. обл.: 48,8 м² → 55,0 м², рост на 13%
-- Чем больше квартира, тем дольше она продаётся


-- Цена за квадратный метр
-- СПб: 108 920 (быстрые) → 114 981 ₽/м² (долгие), рост на 5,56%
-- Лен. обл.: 71 908 (быстрые) → 68 215 ₽/м² (долгие), снижение на 5,14%
-- В СПб цена за м² растёт вместе со сроком экспозиции. В области тенденция обратная: быстрее продаются самые дорогие.



-- Количество комнат
-- СПб: 1,87 → 2,17 комнат
-- Лен. обл.: 1,74 → 2,01
-- Однокомнатные и двухкомнатные квартиры продаются быстрее; трёхкомнатные и более — задерживаются.


-- Количество балконов
-- Среднее число балконов падает с ростом срока:
-- СПб: 1,00 → 0,92
-- Лен. обл.: 1,03 → 0,91
-- Квартиры с балконом привлекательнее и уходят быстрее, причём в области разница заметнее (падение на 0,12 против 0,08 в СПб).

    
-- Высота потолков
-- Практически не меняется (2,70–2,83 м во всех категориях). На скорость продажи не влияет.

    
 -- Этаж
-- Средний этаж снижается с ростом срока экспозиции:
-- СПб: 6,63 → 6,29
-- Лен. обл.: 4,41 → 3,93
-- Квартиры на нижних этажах продаются медленнее. В области эффект заметнее — падение почти на пол-этажа.



-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Продолжите запрос здесь
-- Используйте id объявлений (СТЕ filtered_id), которые не содержат выбросы при анализе данных
dates_flats_id AS (
	SELECT
		re_adv.id AS flats_id,
		extract(MONTH from first_day_exposition) AS date_exp,
		extract(MONTH from (first_day_exposition + days_exposition::int)::date) AS date_remov,
		(re_adv.last_price / re_flats.total_area)::numeric AS square_metr_flat,
		re_flats.total_area AS total_area
	FROM real_estate.advertisement AS re_adv
	INNER JOIN real_estate.flats AS re_flats
		ON re_adv.id = re_flats.id
	INNER JOIN real_estate.city AS re_city
		ON re_flats.city_id = re_city.city_id
	INNER JOIN real_estate.type AS re_type
		ON re_flats.type_id = re_type.type_id
	WHERE 
		re_adv.id IN (SELECT * FROM filtered_id)
		AND extract(YEAR FROM first_day_exposition) IN (2015, 2016, 2017, 2018)
		AND re_type.type = 'город'
),
stat_date_exp AS (
	SELECT
		date_exp as month_exp,
		count(flats_id) AS count_flats_exp,
		round(avg(square_metr_flat)::NUMERIC, 2) AS avg_square_metr_exp,
		round(avg(total_area)::NUMERIC, 2) AS avg_total_area_exp
	FROM dates_flats_id
	GROUP BY 
		date_exp
),
stat_date_remove AS (
	SELECT
		date_remov as month_remov,
		count(flats_id) AS count_flats_remov,
		round(avg(square_metr_flat)::NUMERIC, 2) AS avg_square_metr_remov,
		round(avg(total_area)::NUMERIC, 2) AS avg_total_area_remov
	FROM dates_flats_id
	GROUP BY 
		date_remov
)
SELECT
	CASE 
		WHEN month_exp = 1 THEN 'Январь'
		WHEN month_exp = 2 THEN 'Февраль'
		WHEN month_exp = 3 THEN 'Март'
		WHEN month_exp = 4 THEN 'Апрель'
		WHEN month_exp = 5 THEN 'Май'
		WHEN month_exp = 6 THEN 'Июнь'
		WHEN month_exp = 7 THEN 'Июль'
		WHEN month_exp = 8 THEN 'Август'
		WHEN month_exp = 9 THEN 'Сентябрь'
		WHEN month_exp = 10 THEN 'Октябрь'
		WHEN month_exp = 11 THEN 'Ноябрь'
		WHEN month_exp = 12 THEN 'Декабрь'
	END AS month,
	count_flats_exp,
	avg_square_metr_exp,
	avg_total_area_exp,
	count_flats_remov,
	avg_square_metr_remov,
	avg_total_area_remov
FROM stat_date_exp
full JOIN stat_date_remove
	ON stat_date_exp.month_exp = stat_date_remove.month_remov
ORDER BY 
	month_exp ASC;
-- Сезонность
-- Сезонность публикации объявлений
-- Пиковые месяцы: ноябрь (1 569), октябрь (1 437), февраль (1 369), сентябрь (1 341).
-- Провальные месяцы: январь (735) — в 2 раза меньше, чем в ноябрь; май (891).
   
    
-- Сезонность снятия объявлений (продаж)
-- Пиковые месяцы снятия: октябрь (1 360), ноябрь (1 301), январь (1 225), декабрь (1 175).
-- Январь — аномалия: при минимальном числе публикаций (735) снято больше всего за зиму (1 225).
-- Минимум снятий: май (729) и июнь (771).
    

-- Периоды публикации и продажи
-- Совпадение периодов активной публикации объявлений и периодов повышенной продажи частичное с лагом.
-- Осенний пик (сентябрь–ноябрь) совпадает по обоим направлениям.
-- Есть два несовпадения:
-- Январь — публикаций минимум (735), а снятий третий по величине (1 225). 
-- Это квартиры, выставленные осенью и проданные к январю: снятия «отстают» от публикаций на 2–3 месяца.

-- Февраль — публикаций много (1 369, третий пик), а снятий относительно мало (1 048). 



-- Влияние сезонности на цену и площадь
-- Цена за квадратный метр
-- По публикациям
-- Продавцы выставляют квартиры дороже всего в августе (107 035) – сентябре (107 563). 
-- Дешевле всего — в марте (102 430) – апреле (102 632).


-- По снятиям
-- Квартиры, проданные в марте (106 832) и декабре (105 505), — самые дорогие.  
-- В мае (99 724) – августе (100 037) снятые квартиры самые дешёвые.

-- В большинстве месяцев цена снятых объявлений ниже или близка к цене опубликованных. 
-- Исключение — март (+4 402) и декабрь (+730), когда снятые квартиры дороже опубликованных.
    
 
-- Площадь квартир
-- По публикациям
-- от 58,37 (июнь) до 61,04 (сентябрь). Колебания умеренные — около 2,7.

-- По снятиям
-- от 56,71 (ноябрь) до 61,12 (февраль). Размах больше — 4,4.

-- В 8 из 12 месяцев средняя площадь снятых квартир меньше, чем опубликованных в том же месяце. 
-- Меньшие квартиры продаются быстрее, а более крупные дольше остаются на рынке.

-- Сентябрь выделяется: самые крупные публикации (61,04) при высокой цене (107 563).

-- Чёткой сезонной закономерности нет, но устойчиво прослеживается связь между площадью и скоростью продажи: 
-- чем меньше квартира, тем быстрее её снимают с рынка.
    
    
    
    
-- Общие выводы и рекомендации

-- Выводы

-- Задача 1. Срок экспозиции и характеристики квартир

-- Площадь квартиры - существенный фактор скорости продажи в обоих регионах.

-- Цена — главный фактор скорости продажи в Санкт-Петербурге.
-- Квадратный метр в СПб почти в 1,7 раза дороже.
-- В СПб прослеживается прямая зависимость: чем выше цена за м², тем дольше объект висит на рынке. 
-- В Ленинградской области - зависимость обратная: чем ниже цена за м², тем дольше объект не продается.


-- Малогабаритные квартиры продаются быстрее.
-- Студии и 1–2-комнатные квартиры — самый ликвидный сегмент в обоих регионах.


-- Второстепенные факторы.
-- Балкон - в области наличие балкона влияет на скорость продажи заметнее: разрыв между быстрыми и долгими продажами составляет 0,12 против 0,08 в СПб.

-- Высота потолков - значима только в СПб, в области — не влияет.

-- Этаж - значим только в области: чем ниже средний этаж, тем дольше экспозиция, что связано с отсутствием лифтов в малоэтажной застройке.
-- В СПб средний этаж 6,44 против 4,12 в области — дома выше, квартиры выше. 
-- Но эффект «нижний этаж = дольше продажа» в области выражен сильнее (падение на 0,48 этажа против 0,34 в СПб).

-- Доля долгих объектов (181+ дней) — около 33% в обоих регионах.
-- Это значительная часть рынка.

---

-- Задача 2. Сезонность рынка

-- Осень — главный сезон.
-- Пик публикаций (сентябрь–ноябрь, 4 347 объявлений) и пик снятий (октябрь–ноябрь, 2 661) частично совпадают. 


-- Рынок работает с лагом 1–3 месяца.
-- Январь — минимум публикаций (735), но третий по снятиям (1 225). 
-- Февраль — всплеск публикаций (1 369), но снятий меньше (1 048).

-- Май–июнь: минимум публикаций (891) и снятий (729).

-- Сезонность влияет на цену.
-- Сентябрь - самый дорогой месяц для публикации (107 563).
-- Март - аномалия: снятые квартиры дороже опубликованных на 4 402.
-- Май - самые дешёвые снятия (99 724).


-- Меньшие квартиры продаются быстрее — подтверждается сезонностью.
-- В 8 из 12 месяцев средняя площадь снятых квартир меньше опубликованных в том же месяце. 
-- Малогабаритные квартиры — самый ликвидный сегмент.

---

-- Рекомендации

-- Сезонное планирование.
-- Осенний сезон (сентябрь–ноябрь) — период максимальной активности: концентрировать рекламные бюджеты и кампании здесь. 

-- Таргетинг на малогабаритные квартиры.
-- Студии и 1–2-комнатные квартиры — самый ликвидный сегмент во все сезоны. 

-- Учёт лага при прогнозировании.
-- При планировании продаж учитывать лаг 1–3 месяца от публикации до снятия. 
-- Пик публикаций в ноябре → пик снятий в январе–марте. В декабре–январе много активных объявлений — это нормальный цикл.

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    