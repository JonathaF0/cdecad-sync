--[[
    GTA V vehicle spawn names. Used to build a hash → spawnName reverse
    lookup at script load so ESX sync can convert vehProps.model (a joaat
    hash int) back into a human-readable spawn name. Covers vanilla GTA V
    plus common DLC vehicles. Add custom server vehicles to extend coverage.
]]

VEHICLE_NAMES = {
    -- Compacts
    'blista', 'brioso', 'brioso2', 'brioso3', 'club', 'dilettante', 'dilettante2',
    'issi2', 'issi3', 'issi4', 'issi5', 'issi6', 'issi7', 'issi8', 'panto',
    'prairie', 'rhapsody', 'kanjo',

    -- Sedans
    'asbo', 'asea', 'asea2', 'cog55', 'cog552', 'cognoscenti', 'cognoscenti2',
    'emperor', 'emperor2', 'emperor3', 'fugitive', 'glendale', 'glendale2',
    'ingot', 'intruder', 'premier', 'primo', 'primo2', 'regina', 'romero',
    'schafter2', 'schafter3', 'schafter4', 'schafter5', 'schafter6', 'stafford',
    'stanier', 'stratum', 'stretch', 'super', 'superd', 'surge', 'tailgater',
    'tailgater2', 'warrener', 'warrener2', 'washington',

    -- SUVs
    'baller', 'baller2', 'baller3', 'baller4', 'baller5', 'baller6', 'baller7',
    'bjxl', 'cavalcade', 'cavalcade2', 'contender', 'dubsta', 'dubsta2',
    'dubsta3', 'fq2', 'granger', 'granger2', 'gresley', 'habanero', 'huntley',
    'landstalker', 'landstalker2', 'mesa', 'mesa2', 'mesa3', 'novak', 'patriot',
    'patriot2', 'radi', 'rocoto', 'seminole', 'seminole2', 'serrano', 'toros',
    'xls', 'xls2',

    -- Coupes
    'cogcabrio', 'exemplar', 'f620', 'felon', 'felon2', 'jackal', 'oracle',
    'oracle2', 'sentinel', 'sentinel2', 'sentinel3', 'sentinel4', 'windsor',
    'windsor2', 'zion', 'zion2', 'zion3',

    -- Muscle
    'blade', 'buccaneer', 'buccaneer2', 'chino', 'chino2', 'clique', 'coquette3',
    'deviant', 'dominator', 'dominator2', 'dominator3', 'dominator4', 'dominator5',
    'dominator6', 'dominator7', 'dominator8', 'dukes', 'dukes2', 'dukes3', 'ellie',
    'faction', 'faction2', 'faction3', 'gauntlet', 'gauntlet2', 'gauntlet3',
    'gauntlet4', 'gauntlet5', 'hermes', 'hotknife', 'hustler', 'impaler',
    'impaler2', 'impaler3', 'impaler4', 'lurcher', 'moonbeam', 'moonbeam2',
    'nightshade', 'peyote', 'peyote2', 'peyote3', 'picador', 'phoenix', 'rampagex',
    'ratloader', 'ratloader2', 'ruiner', 'ruiner2', 'ruiner3', 'ruiner4',
    'sabregt', 'sabregt2', 'slamvan', 'slamvan2', 'slamvan3', 'slamvan4',
    'slamvan5', 'slamvan6', 'stalion', 'stalion2', 'tampa', 'tampa3', 'tulip',
    'vamos', 'vigero', 'vigero2', 'virgo', 'virgo2', 'virgo3', 'voodoo',
    'voodoo2', 'yosemite', 'yosemite2', 'yosemite3', 'zr350',

    -- Sports
    'alpha', 'banshee', 'banshee2', 'bestiagts', 'blista2', 'blista3', 'buffalo',
    'buffalo2', 'buffalo3', 'buffalo4', 'carbonizzare', 'comet2', 'comet3',
    'comet4', 'comet5', 'comet6', 'comet7', 'coquette', 'coquette4', 'cyclone2',
    'cypher', 'deveste', 'drafter', 'elegy', 'elegy2', 'emerus', 'eudora',
    'feltzer2', 'flashgt', 'furia', 'furoregt', 'fusilade', 'gauntlet6',
    'growler', 'imorgon', 'infernus2', 'italigto', 'italigtoStinger', 'italirsx',
    'jester', 'jester2', 'jester3', 'jester4', 'jugular', 'kanjosj', 'khamelion',
    'komoda', 'kuruma', 'kuruma2', 'lynx', 'massacro', 'massacro2', 'neo',
    'neon', 'ninef', 'ninef2', 'omnis', 'omnisegt', 'panthere', 'paragon',
    'paragon2', 'pariah', 'penumbra', 'penumbra2', 'phantom', 'rapidgt',
    'rapidgt2', 'rapidgt3', 'raptor', 'remus', 'revolter', 'rt3000', 'ruston',
    'savestra', 'schafter2', 'schlagen', 'schwarzer', 'sentinel3', 'seven70',
    'specter', 'specter2', 'streiter', 'sugoi', 'sultan', 'sultan2', 'sultan3',
    'sultanclassic', 'sultanrs', 'surano', 'tampa2', 'tropos', 'verlierer2',
    'vstr', 'zr3802',

    -- Super
    'adder', 'autarch', 'banshee2', 'bullet', 'champion', 'cheetah', 'cheetah2',
    'cyclone', 'deveste', 'emerus', 'entity2', 'entityxf', 'fmj', 'furia',
    'gp1', 'infernus', 'italigtb', 'italigtb2', 'krieger', 'le7b', 'nero',
    'nero2', 'osiris', 'penetrator', 'pfister811', 'prototipo', 'reaper', 's80',
    'sc1', 'sheava', 't20', 'taipan', 'tempesta', 'tezeract', 'thrax', 'tigon',
    'torero', 'torero2', 'turismo2', 'turismor', 'tyrant', 'tyrus', 'vacca',
    'vagner', 'visione', 'voltic', 'voltic2', 'xa21', 'zentorno', 'zorrusso',

    -- Motorcycles
    'akuma', 'avarus', 'bagger', 'bati', 'bati2', 'bf400', 'carbonrs', 'chimera',
    'cliffhanger', 'daemon', 'daemon2', 'defiler', 'deathbike', 'deathbike2',
    'deathbike3', 'diablous', 'diablous2', 'double', 'enduro', 'esskey', 'faggio',
    'faggio2', 'faggio3', 'fcr', 'fcr2', 'gargoyle', 'hakuchou', 'hakuchou2',
    'hexer', 'innovation', 'lectro', 'manchez', 'manchez2', 'nemesis', 'nightblade',
    'oppressor', 'oppressor2', 'pcj', 'powersurge', 'ratbike', 'ruffian',
    'sanchez', 'sanchez2', 'sanctus', 'shotaro', 'sovereign', 'stryder', 'thrust',
    'vader', 'vindicator', 'vortex', 'wolfsbane', 'zombiea', 'zombieb',

    -- Off-Road
    'bfinjection', 'blazer', 'blazer2', 'blazer3', 'blazer4', 'blazer5',
    'bodhi2', 'brawler', 'caracara', 'caracara2', 'dloader', 'draugur', 'dubsta3',
    'dune', 'dune2', 'dune3', 'dune4', 'dune5', 'everon', 'freecrawler',
    'hellion', 'insurgent', 'insurgent2', 'insurgent3', 'kalahari', 'kamacho',
    'marshall', 'mesa3', 'menacer', 'monster', 'monster3', 'monster4', 'monster5',
    'nightshark', 'outlaw', 'rancherxl', 'rancherxl2', 'rebel', 'rebel2',
    'riata', 'sandking', 'sandking2', 'squaddie', 'technical', 'technical2',
    'technical3', 'trophytruck', 'trophytruck2', 'verus', 'vagrant', 'winky',
    'yosemite2', 'zhaba',

    -- Vans
    'bison', 'bison2', 'bison3', 'bobcatxl', 'boxville', 'boxville2', 'boxville3',
    'boxville4', 'boxville5', 'burrito', 'burrito2', 'burrito3', 'burrito4',
    'burrito5', 'camper', 'gburrito', 'gburrito2', 'journey', 'minivan',
    'minivan2', 'paradise', 'pony', 'pony2', 'rumpo', 'rumpo2', 'rumpo3',
    'speedo', 'speedo2', 'speedo4', 'surfer', 'surfer2', 'taco', 'youga', 'youga2',
    'youga3',

    -- Trucks / Commercial
    'benson', 'biff', 'cerberus', 'cerberus2', 'cerberus3', 'flatbed', 'guardian',
    'hauler', 'hauler2', 'mixer', 'mixer2', 'mule', 'mule2', 'mule3', 'mule4',
    'packer', 'phantom', 'phantom2', 'phantom3', 'pounder', 'pounder2', 'rubble',
    'scrap', 'stockade', 'stockade3', 'terbyte', 'tiptruck', 'tiptruck2',
    'trash', 'trash2',

    -- Service / Emergency
    'ambulance', 'firetruk', 'pbus', 'pbus2', 'police', 'police2', 'police3',
    'police4', 'police5', 'policeb', 'policeold1', 'policeold2', 'policet',
    'predator', 'pranger', 'riot', 'riot2', 'sheriff', 'sheriff2', 'fbi', 'fbi2',
    'lguard', 'rangerx',

    -- Utility
    'airtug', 'caddy', 'caddy2', 'caddy3', 'docktug', 'forklift', 'mower',
    'ripley', 'sadler', 'sadler2', 'scrap', 'towtruck', 'towtruck2', 'tractor',
    'tractor2', 'tractor3', 'utillitruck', 'utillitruck2', 'utillitruck3',
    'fieldmaster', 'flatbed',

    -- Industrial
    'bulldozer', 'cutter', 'dump', 'handler', 'tipper', 'rubble',

    -- Public Transit
    'airbus', 'bus', 'coach', 'rentalbus', 'taxi', 'tourbus', 'wastelander',

    -- Aircraft
    'akula', 'alphaz1', 'annihilator', 'annihilator2', 'avenger', 'avenger2',
    'besra', 'blimp', 'blimp2', 'blimp3', 'bombushka', 'buzzard', 'buzzard2',
    'cargobob', 'cargobob2', 'cargobob3', 'cargobob4', 'cargoplane', 'cuban800',
    'dodo', 'duster', 'frogger', 'frogger2', 'havok', 'howard', 'hunter',
    'jet', 'lazer', 'luxor', 'luxor2', 'maverick', 'microlight', 'miljet',
    'mogul', 'molotok', 'nimbus', 'nokota', 'pyro', 'rogue', 'savage', 'seabreeze',
    'shamal', 'skylift', 'starling', 'strikeforce', 'stunt', 'supervolito',
    'supervolito2', 'swift', 'swift2', 'titan', 'tula', 'velum', 'velum2',
    'vestra', 'volatus',

    -- Boats
    'avisa', 'dinghy', 'dinghy2', 'dinghy3', 'dinghy4', 'jetmax', 'kosatka',
    'longfin', 'marquis', 'patrolboat', 'predator', 'seashark', 'seashark2',
    'seashark3', 'speeder', 'speeder2', 'squalo', 'submersible', 'submersible2',
    'suntrap', 'toro', 'toro2', 'tropic', 'tropic2', 'tug',

    -- Misc / Special
    'ardent', 'brioso', 'brioso2', 'bruiser', 'bruiser2', 'bruiser3', 'btype',
    'btype2', 'btype3', 'casco', 'cheburek', 'coquette2', 'cyclone', 'dynasty',
    'fagaloa', 'gt500', 'hotring', 'jb700', 'jb7002', 'manana', 'manana2',
    'michelli', 'mamba', 'monroe', 'nebula', 'peyote', 'pigalle', 'rapidgt3',
    'retinue', 'retinue2', 'rhinehart', 'rumpo3', 'savestra', 'stafford',
    'stinger', 'stingergt', 'stromberg', 'thrust', 'tornado', 'tornado2',
    'tornado3', 'tornado4', 'tornado5', 'tornado6', 'tropos', 'vigero',
    'viseris', 'voltic', 'z190', 'ztype',
}

return VEHICLE_NAMES
