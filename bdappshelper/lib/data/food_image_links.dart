// =====================================================================
// Amar Diet — Food Image Links Registry
// =====================================================================
//
// THIS IS THE ONLY FILE YOU NEED TO EDIT TO ADD FOOD IMAGES.
//
// Just paste a full https:// image URL as the value for each food id.
// Use a free image host such as:
//   - https://i.ibb.co/XXXXX/foodname.jpg
//   - https://i.imgur.com/XXXXX.png
//   - https://upload.wikimedia.org/wikipedia/commons/...
//
// If a food has no URL (value is empty) the app will fall back to a
// pretty gradient + icon — so nothing breaks while you're adding links.
//
// Tip: keep the same width/height for all images (e.g. 800x600) for a
// consistent, professional grid look.
// =====================================================================

class FoodImageLinks {
  FoodImageLinks._();

  /// Default placeholder when no image is set.
  /// Replace with your own bundled asset path if you prefer.
  static const String placeholder =
      'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=800';

  /// Image URL for each food id. Edit freely.
  static const Map<String, String> links = {
    // -------- Rice & breads --------
    'rice_plain':   'https://plus.unsplash.com/premium_photo-1675814316651-3ce3c6409922?q=80&w=1036&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D?w=800',
    'roti':         'https://plus.unsplash.com/premium_photo-1675382377369-c8f4cd69cfee?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'biryani':      'https://images.unsplash.com/photo-1589302168068-964664d93dc0?q=80&w=987&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'khichuri':     'https://images.unsplash.com/photo-1630409351211-d62ab2d24da4?q=80&w=1013&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'paratha':      'https://images.unsplash.com/photo-1668357530437-72a12c660f94?q=80&w=987&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'luchi':        'https://images.unsplash.com/photo-1676700310660-e92d03e259c3?q=80&w=2050&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'pulao':        'https://images.unsplash.com/photo-1645177628172-a94c1f96e6db?q=80&w=927&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'porota':       'https://www.haleemeats.com/wp-content/uploads/2022/09/IMG_0581-4.jpg',

    // -------- Curries & dals --------
    'chicken_curry':  'https://images.unsplash.com/photo-1603894584373-5ac82b2ae398?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'beef_curry':     'https://images.unsplash.com/photo-1534939561126-855b8675edd7?q=80&w=987&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'mutton_curry':   'https://images.unsplash.com/photo-1606843046080-45bf7a23c39f?q=80&w=987&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
    'lentil_dal':     'https://www.cookwithmanali.com/wp-content/uploads/2025/02/Red-Masoor-Dal-In-a-Pan-topped-with-tadka-1200x1818.jpg',
    'cholar_dal':     'https://cdn2.foodviva.com/static-content/food-images/daal-kadhi-recipes/cholar-dal/cholar-dal.jpg',
    'mixed_veg':      'https://www.cookwithmanali.com/wp-content/uploads/2023/01/Mixed-Veg-Sabzi.jpg',
    'potato_curry':   'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSkC3_6EzlGw76zYUUHQnZchf8v8tWIann0pZkeUxRoxxBgIQqaQ4r2v0EQ&s=10',
    'egg_curry':      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRn7mzTZ17YgwTvFMZhnvPkkHjzDMP4EeebDuXLbB_tBTfAMlrRYW82PiE&s=10',

    // -------- Fish & seafood --------
    'hilsa_fish':     'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRkPf92C4suZs2HNRF-EmmAi3AbnaTz02cBGfNG54zFjw&s=10',
    'rui_fish':       'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQyU5989YVhQ30nxUYmmZhDEs0uInTExepfnQntr9zh5uGQm2BlXKggY1Q9&s=10',
    'ilish_patla':    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcR9oX6EcWGirjQ6SdAHhAGtjbiHsEYy7s6YI6fEF21XU65-dDzuloGhw0N5&s=10',
    'chingri':        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQ7xybAHMrxqoFPw8NG2aTC-_SdH6_Ber4NGrJGAImZkvQgUh6tah3SDAw&s=10',
    'koi_fish':       'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSB1mQmnasIdjs_uMmm9rgbCeXGvSXOM4nm3pB9iHGu2OuYSDJWQMdN1nw&s=10',
    'pangash':        'https://nahidsworld.com/upload/fishes/variants/range_42_1784561750.png',
    'tilapia':        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRZp7SvDKz3hijZ4RpQZ2tggQ6cz37s3bj__21gu7yJW9P00kQAPisydnQ&s=10',

    // -------- Meat --------
    'boiled_egg':     'https://www.seriouseats.com/thmb/Mzkc2-5ELWaYFv7XhhbHZMYukXU=/1500x0/filters:no_upscale():max_bytes(150000):strip_icc()/steamed-hard-boiled-egg-hero-b19792d9bf7344978dd043e6a8f9c074.JPG',
    'fried_egg':      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSzNlcsa4m59U2_yIoHcpyzw1-pMzcSLl85vnNaF6q--kJeMnaNJ286Y1g&s=10',
    'chicken_bbq':    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSDvS8XZH3SaaoipD9FVEXp302XqrPnbYXhtQJyJXJybrW8u7_oKivFewM&s=10',
    'kacchi_biryani': 'https://media.licdn.com/dms/image/v2/D5622AQH2PrpvtMQNAA/feedshare-shrink_800/feedshare-shrink_800/0/1723486642754?e=2147483647&v=beta&t=QmvdWv74H0_wndb0qSRYujYYZ-FsK1dzG9fnv6l5gq4',

    // -------- Dairy --------
    'milk':           'https://media.istockphoto.com/id/1222018207/photo/pouring-milk-into-a-drinking-glass.jpg?s=612x612&w=0&k=20&c=eD4YHoSjKIYSPDgnM2OgWD_HVH2IcmjZSRq7IjUnH6M=',
    'curd':           'https://www.yummytummyaarthi.com/wp-content/uploads/2023/10/yogurt-1-500x500.jpg',
    'sweet_yogurt':   'https://www.banglakutir.com/app-contents/upload/1/products/1642952558_1_1_2029366921.jpg',
    'cheese':         'https://blog.wisconsincheeseman.com/wp-content/uploads/2022/10/sharp-cheddar-baby-swiss-1-edited.jpg.webp',

    // -------- Fruits --------
    'banana':         'https://nutritionsource.hsph.harvard.edu/wp-content/uploads/2018/08/bananas-1354785_1920-1024x683.jpg',
    'apple':          'https://cdn.britannica.com/22/187222-050-07B17FB6/apples-on-a-tree-branch.jpg',
    'mango':          'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRFzNp_QCdodl6ZFADbwAtc_JbmeJwGIsT9GD0dTZPgpEegYq8ggD67sPuP&s=10',
    'orange':         'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSn1TAG_z2fGZSQvuwbDjq-LtDhQgdRBtWXQtg-pTJMlQ&s=10',
    'watermelon':     'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTVg98U-SKCwet1B85WK8zCOXeI6mwYe-zb5Fo9oYl8yA&s',
    'papaya':         'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSvESV0qO1tFZtBZwSMnS59vqdA-ULiy2ufL2aNr0eUovmwUk4eF9f57TY&s=10',
    'guava':          'https://www.finedininglovers.co.uk/sites/default/files/styles/1_1_768x768/public/article_content_images/guava%C2%A9iStock.jpg.webp?itok=E5JtI95S',
    'pineapple':      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQDoOHvM2a1FQgTr9spqPJdRQ5Os1871zVRnA-7eVQQiNBwlI2X3XNp_0Tw&s=10',
    'jackfruit':      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQsmcbADQj9Mk34ZhWJ6Wy4OU58Xk7LdriCDKhr09zKOQcMMZIW-U4RPMRA&s=10',
    'lychee':         'https://cdn.britannica.com/18/176518-050-5AB1E61D/lychee-fruits-Southeast-Asia.jpg',
    'coconut':        'https://www.paperandtea.com/cdn/shop/articles/Kokosnuss_00dc9916-deb3-4cfe-8151-107fc85f6136.jpg?v=1756478271&width=1500',

    // -------- Vegetables & salads --------
    'cucumber':       'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcR44Y7xhsVwE6NAumRZ6yeZdxK1TYO8iGrLbO5_YlfobmXnFatleab6TDDP&s=10',
    'tomato':         'https://images-prod.healthline.com/hlcmsresource/images/AN_images/tomatoes-1296x728-feature.jpg',
    'carrot':         'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRXFVK8dvtUhad32iGjTZa1zZhQp2faKJC0nXsCDH7u4zrshHAfodsCG5M&s=10',
    'spinach':        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTbu2iey1u00EbdxTrMcLeJk1zHpKh30AN87KWEDcxMYUPxksRAntFX04s&s=10',
    'pumpkin_veg':    'https://i.ytimg.com/vi/_KG8gY3oN4w/hq720.jpg?sqp=-oaymwEhCK4FEIIDSFryq4qpAxMIARUAAAAAGAElAADIQj0AgKJD&rs=AOn4CLCkch8uRaA_ILHIYs3wbYwZZUkdzQ',
    'okra':           'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSxf-ogRKvb4C_fMfk57xZxBN2uwQoN5bvKXfOodJX6ZcUWy_0ipe82gOlW&s=10',
    'eggplant':       'https://foolproofliving.com/wp-content/uploads/2023/03/sauteed-eggplant-recipe.jpg',
    'bitter_gourd':   'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcT-tlEYl0r72ZO7-01t2gjhPpEU14iTCCXsVTneSyOgGdT7h4LHjYBFn8o4&s=10',
    'salad':          'https://www.tasteofhome.com/wp-content/uploads/2025/02/Favorite-Mediterranean-Salad_EXPS_TOHcom25_41556_MD_P2_02_05_1b.jpg',

    // -------- Snacks & street food --------
    'samosa':         'https://www.indianhealthyrecipes.com/wp-content/uploads/2021/12/samosa-recipe-480x270.jpg',
    'singara':        'https://www.vegrecipesofindia.com/wp-content/uploads/2017/12/singara-recipe-2.jpg',
    'fuchka':         'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcStazt0SGO8Fv9MmP9lmdVhrXZwodOY74L3obWjYcdhyZT0VDhKVefcaan-&s=10',
    'chotpoti':       'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTjSFtCd11Rz4H7PUMBCvGd1-FAcVrKnJWnehb6CimIAEFGGgrc0RpYXliR&s=10',
    'jhalmuri':       'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQYPwljQGZOSl0SCtdvtn7OSKRBvHhi9wMOUnOOq2neX3ghLsFHvlr_ghs&s=10',
    'beguni':         'https://www.vegrecipesofindia.com/wp-content/uploads/2026/02/beguni-recipe-1.jpg',
    'peyaji':         'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQBFKF_dJ3CUYRJ8b-uDh1-IchoULoiiOWygXtFmvStkjHEkbQrlLJEEXU&s=10',
    'pitha':          'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcS6AGxyd3mo-ybP_rW7486xZZoMQeju3op2Pd3-KQbDQYejdoulzzRRVdn4&s=10',
    'roshogolla':     'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSgcNxfJDKdZXPQpgUBcUbzeiPN87C42BaP0y6Fq6ktw0Prqs9kS_BZK-nR&s=10',
    'sandesh':        'https://cdn1.foodviva.com/static-content/food-images/bengali-recipes/sandesh-sondesh/sandesh-sondesh.jpg',
    'mishti_doi':     'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSaLfwRDogM_Q2h1u-wFAECby2_iKCc8Jhuzx22GxMbedcksuHQ4PVz4Js&s=10',
    'rasmalai':       'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcS9JR_wYkYg6lE9UK-syroVNdWjtWT0kpixr0PbUllh0XzpUJGpo88UZPhp&s=10',

    // -------- Drinks --------
    'tea_sugar':      'https://media.istockphoto.com/id/114412157/photo/spoonful-with-sugar-over-mug-of-tea.jpg?s=612x612&w=0&k=20&c=6fCEOWtaqVUrr--gW7B4R_HIdeysKZ_gegv7EEl51gI=',
    'milk_tea':       'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcT1ZrNsJtr2Kzhwg4AIh6aTfoQ9X4y5pHRen_1XRAbEtKOxCQcyaPxLHoo&s=10',
    'lemon_water':    'https://www.thekitchenmagpie.com/wp-content/uploads/images/2021/01/lemonwater1.jpg',
    'mango_juice':    'https://www.crazyvegankitchen.com/wp-content/uploads/2023/06/mango-juice-683x1024.jpg',
    'sugarcane_juice':'https://juicernet.com/wp-content/uploads/2022/08/sFw1zSLlqpVbvFytZQWdmkniIuBZzXLW1659961246-scaled.jpeg',
    'borhani':        'https://www.seriouseats.com/thmb/sUOfP39og6FG1ibR61zW4KSnf08=/1500x0/filters:no_upscale():max_bytes(150000):strip_icc()/20171220-salted-mint-lassi-borhani-vicky-wasik-SEA-4I8A5025-79df6d0cd52d4eaebe17e64453b68f7e.jpg',
    'lassi':          'https://fogandfeast.com/wp-content/uploads/2020/04/pistachio-lassi-in-tall-glass.jpg',
    'coffee':         'https://colombiancoffee.us/cdn/shop/articles/tips-to-recognize-good-quality-coffee-424970.png?v=1713377616',
    'green_tea':      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSjqZAW6du_yVsOYwBXxkB4d95S0MowXOyTMmY6SBz_o9OG0Hj-eCpArX_o&s=10',

    // -------- Sweets / desserts --------
    'firni':          'https://www.whiskaffair.com/wp-content/uploads/2020/07/Phirni-2-3.jpg',
    'payesh':         'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSmnOsbdyTXV1qX2B56F_kTo3jbP_-yfgqZuQvs5PHMIwiCzTbCxLHm5xw&s=10',
    'halwa':          'https://www.cookwithmanali.com/wp-content/uploads/2016/10/Karachi-Halwa-Bombay-Halwa.jpg',

    // -------- Festival & traditional --------
    'panta_bhat':       'https://upload.wikimedia.org/wikipedia/commons/e/e6/Panta_Ilish.jpg?utm_source=en.wikipedia.org&utm_campaign=index&utm_content=original', // Pohela Boishakh special
    'naru':             'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSZ-Ds4psgHsNhN0sptnkeozgG18LGF9gyztGGa0NOmCq0UpzvfZJc1bIuc&s=10', // Coconut laddu
    'chitoi_pitha':     'https://www.upoharbd.com/images/uploads/Pitha/dudh_chitoi.jpg',
    'vapa_pitha':       'https://i.ytimg.com/vi/RE82tbUFRe4/oardefault.jpg?usqp=CCk',
    'patishapta':       'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQIGRM1Gg0MOa22PHszyV1R9vYuWvSJy-V6m59QhwJvfw&s=10',
    'dudh_puli':        'https://i.ytimg.com/vi/UHymOqlRcD4/maxresdefault.jpg',
    'naricher_chop':    'https://i.ytimg.com/vi/Z0t3SeL9xcY/hq720.jpg?sqp=-oaymwEhCK4FEIIDSFryq4qpAxMIARUAAAAAGAElAADIQj0AgKJD&rs=AOn4CLBPi-FUj3saVSMwKuKgljBCrCzVYg',

    // -------- Regional dishes --------
    'chui_jhal':        'https://img.drz.lazcdn.com/static/bd/p/5af18147d3ec961d487646b66c93e7de.jpg_720x720q80.jpg', // Sylhet specialty
    'chittagong_beef':  'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQzKMfXv8-ICBxhmW96hJE8GKd5vPwLiIgXhoNl4SpsUsW3CBGuIHxM_ZEw&s=10', // Chittagong classic
    'mekhla_chutney':   'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRXZDv9bmoVwXpZx_l4JCEUyz2BYGUJnygnL4mvWmVOtCwLiQ0tSacak-gj&s=10', // Sylhet chutney
    'shidol_patla':     'https://i.ytimg.com/vi/XGcfnjD1Y7g/hq720.jpg?sqp=-oaymwEhCK4FEIIDSFryq4qpAxMIARUAAAAAGAElAADIQj0AgKJD&rs=AOn4CLADnAxbjxBdjUBaqE4JrUJ-N0ngKg', // Fermented shrimp curry

    // -------- More street food --------
    'chicken_roll':     'https://www.licious.in/blog/wp-content/uploads/2022/12/Shutterstock_2132499279-600x600.jpg',
    'beef_shawarma':    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSXjlkgEPFsxePCAfRFJGJCIyeKR5Gj990sK1vdienUbCmTCPG0cADnk6k&s=10',
    'bhel_puri':        'https://i.ytimg.com/vi/OV9UDiczSwU/hq720.jpg?sqp=-oaymwEhCK4FEIIDSFryq4qpAxMIARUAAAAAGAElAADIQj0AgKJD&rs=AOn4CLCYL2LftrcKNIRpTXF7p9yL3VF2Mg',
    'pani_puri':        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQvGF72X0F_Vwb7yjbEpyOuvG9D4iE6_VS87nmOGFMjXQ&s',
    'egg_chop':         'https://i.ytimg.com/vi/GIo2KGSmidI/hq720.jpg?sqp=-oaymwEhCK4FEIIDSFryq4qpAxMIARUAAAAAGAElAADIQj0AgKJD&rs=AOn4CLBJeZX1DepJQWqTdm1yG6kL26OWIg',
    'fish_chop':        'https://www.licious.in/blog/wp-content/uploads/2023/01/shutterstock_2197404569-750x500.jpg',
    'aloo_chop':        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSVEaGCIlhpZr8auGxqRfiDmFVuIr-j8ScrTF9I2JZ0KfjC-QQR7o_-F8Y&s=10',
    'golap_cha':        'https://i.ytimg.com/vi/I2o6g3K3AUY/maxresdefault.jpg',

    // -------- Healthy additions --------
    'oats_bowl':        'https://i.ytimg.com/vi/OswmGOop3o8/hq720.jpg?sqp=-oaymwEhCK4FEIIDSFryq4qpAxMIARUAAAAAGAElAADIQj0AgKJD&rs=AOn4CLB9a013zAaHz5ZvhEeOjuLoXwTmAQ',
    'sprouts_chaat':    'https://limethyme.com/wp-content/uploads/2022/03/Sprouts-chaat-06.jpg',
    'green_smoothie':   'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSPvRZHqz7qjS7ZFWw0H0p0gxyWl6IpJzdh-ZdvStUhXdStNPpb6ZpyYUr0&s=10',
    'chia_pudding':     'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTPt4_gyVEfMbF27bzsw4RUsUTBC8t9ObfuYbi3LCRpkm_U7b8x9Vf6RkY&s=10',
  };

  /// Returns the URL for a given food id, or the placeholder if none set.
  static String urlFor(String id) {
    final u = links[id];
    if (u == null || u.isEmpty) return placeholder;
    return u;
  }
}
