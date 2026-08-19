const fs = require('fs');
const path = 'c:/Users/Nazmul/StudioProjects/diabetics_meal-main/lib/screens/meal_plan_screen.dart';
let log = '';
try {
  const d = fs.readFileSync(path, 'utf8');
  const obsStart = d.indexOf('/// OBSOLETE');
  const slotStart = d.indexOf('/// Horizontal chip strip');
  log += 'obsStart=' + obsStart + ' slotStart=' + slotStart + '\n';
  if (obsStart > 0 && slotStart > obsStart) {
    let cutFrom = obsStart;
    while (cutFrom > 0 && d[cutFrom - 1] !== '\n') cutFrom--;
    if (cutFrom >= 2 && d[cutFrom - 1] === '\n' && d[cutFrom - 2] === '\n') cutFrom -= 1;
    const out = d.slice(0, cutFrom) + d.slice(slotStart);
    fs.writeFileSync(path, out, 'utf8');
    log += 'OK stripped ' + (cutFrom - obsStart) + ' chars; new length ' + out.length + '\n';
  } else {
    log += 'NO MATCH\n';
  }
} catch (e) {
  log += 'ERR ' + e.message + '\n';
}
fs.writeFileSync('c:/Users/Nazmul/StudioProjects/diabetics_meal-main/scripts/strip_log.txt', log, 'utf8');