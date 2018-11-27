import requestAnimationFrame from 'raf';
import now from 'performance-now';
import xs from 'xstream';

export default function timeDriver () {
  const animation$ = xs.create();

  let previousTime = new Date().getTime();

  function tick () {
    let timestamp = new Date().getTime();

    animation$.shamefullySendNext({
      timestamp,
      delta: timestamp - previousTime
    });

    previousTime = timestamp;

    requestAnimationFrame(tick);
  }

  tick();

  return animation$;
}

