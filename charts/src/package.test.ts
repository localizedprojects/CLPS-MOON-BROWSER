// L5 (1.13.4): the chart package says its licence (the repository's, MIT) and
// carries the app's name, in package.json and in the lock's root entry.
import { describe, expect, it } from 'vitest'
import lock from '../package-lock.json'
import pkg from '../package.json'
import licence from '../../LICENSE?raw'

describe('the chart package manifest (L5)', () => {
  it('is MIT, the licence of the repository', () => {
    expect(licence.split('\n')[0].trim()).toBe('MIT License')
    expect(pkg.license).toBe('MIT')
    expect(lock.packages[''].license).toBe('MIT')
  })
  it('is named for Lunar Horizon, the same in the lock', () => {
    expect(pkg.name).toBe('lunar-horizon-charts')
    expect(lock.name).toBe(pkg.name)
    expect(lock.packages[''].name).toBe(pkg.name)
    expect(pkg.private).toBe(true)
  })
})
